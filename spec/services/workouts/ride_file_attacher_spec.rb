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
    expect(activity).to have_attributes(
      user: workout.training_plan.user,
      planned_workout: workout,
      source: "upload",
      sport: "cycling",
      link_origin: "rider",
      started_on: Date.new(2026, 8, 25),
      figures_ftp_watts: 260)
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

    expect(Activity.where(planned_workout: workout).count).to eq(1)
    expect(activity.ride_file.filename.to_s).to eq("indoor_ride.fit")
    expect(activity.elapsed_seconds).to eq(2715)
    expect(activity.tss.to_f).to be_within(0.1).of(37.8)
  end

  it "stores a ride without power with duration and heart rate only" do
    activity = described_class.new(workout: workout, file: upload("outdoor_ride_without_power")).call

    expect(activity.power?).to be(false)
    expect(activity.average_heart_rate_bpm.to_f).to be_within(0.5).of(142)
  end

  describe "GAR-005 upload after Garmin" do
    let(:user) { workout.training_plan.user }

    # outdoor_ride.fit starts at 09:30:22 UTC on 25 August 2026.
    def garmin_ride(started_at:, **attributes)
      create(
        :activity,
        :unlinked,
        user: user,
        source: :garmin,
        garmin_activity_id: 25_000_000_001,
        started_at: started_at,
        **attributes).tap { |activity| activity.ride_file.purge }
    end

    it "links an unlinked activity starting within 60 seconds instead of creating a second record" do
      existing = garmin_ride(started_at: Time.utc(2026, 8, 25, 9, 31, 20))
      attacher = described_class.new(workout: workout, file: upload("outdoor_ride"))

      activity = attacher.call

      expect(activity).to eq(existing)
      expect(attacher).to be_linked_existing
      expect(Activity.count).to eq(1)
      expect(activity.reload).to have_attributes(
        planned_workout: workout,
        link_origin: "rider",
        source: "garmin",
        garmin_activity_id: 25_000_000_001,
        figures_ftp_watts: 260)
      expect(activity.ride_file.filename.to_s).to eq("outdoor_ride.fit")
      expect(activity.np_watts.to_f).to be_within(0.5).of(227.4)
    end

    it "keeps the matching activity's stored file" do
      existing = garmin_ride(started_at: Time.utc(2026, 8, 25, 9, 29, 30))
      existing.ride_file.attach(io: file_fixture("fit/indoor_ride.fit").open, filename: "garmin.fit")
      existing.save!

      activity = described_class.new(workout: workout, file: upload("outdoor_ride")).call

      expect(activity.ride_file.filename.to_s).to eq("garmin.fit")
      expect(activity.elapsed_seconds).to eq(2715)
      expect(ActiveStorage::Blob.count).to eq(1)
    end

    it "keeps activities more than 60 seconds apart separate" do
      existing = garmin_ride(started_at: Time.utc(2026, 8, 25, 9, 31, 23))

      activity = described_class.new(workout: workout, file: upload("outdoor_ride")).call

      expect(activity).not_to eq(existing)
      expect(existing.reload.planned_workout).to be_nil
    end

    it "matches only cycling activities" do
      walk = garmin_ride(started_at: Time.utc(2026, 8, 25, 9, 30, 22), sport: :walking)

      activity = described_class.new(workout: workout, file: upload("outdoor_ride")).call

      expect(activity).not_to eq(walk)
      expect(walk.reload.planned_workout).to be_nil
    end

    it "prefers an unlinked match over a closer ride linked elsewhere" do
      other = create(:planned_workout, :completed, training_plan: workout.training_plan, scheduled_on: workout.scheduled_on + 1)
      garmin_ride(started_at: Time.utc(2026, 8, 25, 9, 30, 22)).then { |ride| Activities::Linker.new(ride).link!(other, origin: :automatic) }
      unlinked = garmin_ride(started_at: Time.utc(2026, 8, 25, 9, 31, 0), garmin_activity_id: 25_000_000_002)

      expect(described_class.new(workout: workout, file: upload("outdoor_ride")).call).to eq(unlinked)
    end

    it "rejects an upload matching a ride kept with an archived plan, without offering Change ride" do
      archived = create(:training_plan, :archived, user: user, starts_on: workout.training_plan.starts_on - 100, ends_on: workout.training_plan.starts_on - 30)
      old = create(:planned_workout, :completed, training_plan: archived, scheduled_on: archived.starts_on + 1, name: "Old ride")
      garmin_ride(started_at: Time.utc(2026, 8, 25, 9, 30, 22)).then { |ride| Activities::Linker.new(ride).link!(old, origin: :automatic) }

      expect { described_class.new(workout: workout, file: upload("outdoor_ride")).call }
        .to raise_error(described_class::Rejected, "This ride is already linked to Old ride on #{old.scheduled_on.to_fs(:long)} in an archived plan.")
    end

    it "ignores another rider's activity" do
      someone_elses = create(:activity, :unlinked, source: :garmin, garmin_activity_id: 1, started_at: Time.utc(2026, 8, 25, 9, 30, 22))

      activity = described_class.new(workout: workout, file: upload("outdoor_ride")).call

      expect(activity).not_to eq(someone_elses)
      expect(someone_elses.reload.planned_workout).to be_nil
    end

    it "rejects an upload matching a ride linked to another workout" do
      other = create(:planned_workout, :completed, training_plan: workout.training_plan, scheduled_on: workout.scheduled_on + 1, name: "Long ride")
      garmin_ride(started_at: Time.utc(2026, 8, 25, 9, 30, 22)).then { |ride| Activities::Linker.new(ride).link!(other, origin: :automatic) }

      expect { described_class.new(workout: workout, file: upload("outdoor_ride")).call }
        .to raise_error(described_class::Rejected, "This ride is already linked to Long ride on #{other.scheduled_on.to_fs(:long)}. Use Change ride to move it.")
      expect(workout.reload.activity).to be_nil
    end

    it "rejects an upload to a workout with a Garmin ride linked" do
      Activities::Linker.new(garmin_ride(started_at: Time.utc(2026, 8, 20, 9))).link!(workout, origin: :automatic)

      expect { described_class.new(workout: workout, file: upload("outdoor_ride")).call }
        .to raise_error(described_class::Rejected, "Unlink the Garmin ride first.")
      expect(workout.reload.activity.ride_file).not_to be_attached
    end
  end

  describe "rejection" do
    def expect_rejection(target, file, message)
      expect { described_class.new(workout: target, file: file).call }.to raise_error(described_class::Rejected, message)
      expect(Activity.count).to eq(0)
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
