require "rails_helper"

RSpec.describe Workouts::RideFileAttacher, type: :service do
  let(:workout) { create(:planned_workout, :completed) }

  def upload(name)
    Rack::Test::UploadedFile.new(file_fixture("fit/#{name}.fit"), "application/octet-stream", true)
  end

  def history(workout)
    workout.reload
    [ workout.attributes, workout.workout_steps.map(&:attributes), workout.workout_feedback.attributes ]
  end

  it "stores ridden metrics at the completion FTP without changing completed history" do
    create(:rider_profile, user: workout.training_plan.user, ftp_watts: 300)
    before = history(workout)

    activity = described_class.new(workout: workout, file: upload("outdoor_ride")).call

    expect(activity).to be_persisted
    expect(activity.ride_file.filename.to_s).to eq("outdoor_ride.fit")
    expect(activity.ride_file.download.byteslice(8, 4)).to eq(".FIT")
    expect(activity).to have_attributes(elapsed_seconds: 2934, moving_seconds: 2817, started_at: Time.utc(2026, 8, 25, 9, 30, 22))
    expect(activity.np_watts.to_f).to be_within(0.5).of(227.4)
    expect(activity.intensity_factor.to_f).to be_within(1e-4).of(activity.np_watts.to_f / 260)
    expect(activity.date_mismatch?).to be(true)
    expect(history(workout)).to eq(before)
  end

  it "replaces an earlier ride file and its metrics" do
    described_class.new(workout: workout, file: upload("outdoor_ride")).call

    activity = described_class.new(workout: workout, file: upload("indoor_ride")).call

    expect(WorkoutActivity.where(planned_workout: workout).count).to eq(1)
    expect(activity.ride_file.filename.to_s).to eq("indoor_ride.fit")
    expect(activity.elapsed_seconds).to eq(2715)
    expect(activity.tss.to_f).to be_within(0.1).of(37.8)
  end

  it "stores a ride without power with duration and heart rate only" do
    activity = described_class.new(workout: workout, file: upload("outdoor_ride_without_power")).call

    expect(activity.power?).to be(false)
    expect(activity.average_heart_rate_bpm.to_f).to be_within(0.5).of(142)
  end

  describe "rejection" do
    def expect_rejection(target, file, message)
      expect { described_class.new(workout: target, file: file).call }.to raise_error(described_class::Rejected, message)
      expect(WorkoutActivity.count).to eq(0)
      expect(ActiveStorage::Blob.count).to eq(0)
    end

    it "rejects a missing file" do
      expect_rejection(workout, nil, "Choose a FIT file to upload")
    end

    it "rejects files over 10 MB before reading them" do
      large = instance_double(ActionDispatch::Http::UploadedFile, size: 10.megabytes + 1)
      allow(large).to receive(:read)

      expect_rejection(workout, large, "Ride files must be 10 MB or smaller")
      expect(large).not_to have_received(:read)
    end

    it "rejects files that are not valid FIT activities" do
      text = Rack::Test::UploadedFile.new(StringIO.new("not a ride"), "text/plain", original_filename: "ride.fit")

      expect_rejection(workout, text, "Not a FIT file")
    end

    it "rejects workouts that are not completed" do
      planned = create(:planned_workout, :structured)

      expect_rejection(planned, upload("outdoor_ride"), "Only completed workouts accept ride files")
    end
  end
end
