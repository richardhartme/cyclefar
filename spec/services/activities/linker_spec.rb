require "rails_helper"

RSpec.describe Activities::Linker, type: :service do
  let(:user) { create(:user) }
  let(:profile) { create(:rider_profile, user: user, ftp_watts: 300) }
  let(:plan) { create(:training_plan, user: user) }
  let(:workout) { create(:planned_workout, :completed, training_plan: plan, scheduled_on: Date.new(2026, 9, 10)) }
  let(:other_workout) { create(:planned_workout, :completed, training_plan: plan, scheduled_on: Date.new(2026, 9, 12)) }

  # outdoor_ride.fit starts on 25 August 2026 with an NP of about 227 W.
  def unlinked_ride
    create(:activity, :unlinked, user: user).tap do |activity|
      activity.ride_file.attach(io: file_fixture("fit/outdoor_ride.fit").open, filename: "outdoor_ride.fit")
    end
  end

  def history(record)
    record.reload
    [ record.attributes, record.workout_steps.map(&:attributes), record.workout_feedback.attributes ]
  end

  before do
    create(:ftp_reading, rider_profile: profile, ftp_watts: 250, effective_on: Date.new(2026, 8, 1))
    create(:ftp_reading, rider_profile: profile, ftp_watts: 300, effective_on: Date.new(2026, 9, 1))
  end

  it "FBK-004 links a ride and recalculates its figures at the workout's frozen completion FTP" do
    ride = unlinked_ride
    before = history(workout)

    described_class.new(ride).link!(workout, origin: :rider)

    expect(ride.reload).to have_attributes(planned_workout: workout, link_origin: "rider", figures_ftp_watts: 260)
    expect(ride.np_watts.to_f).to be_within(0.5).of(227.4)
    expect(ride.intensity_factor.to_f).to be_within(1e-3).of(227.4 / 260)
    expect(history(workout)).to eq(before)
  end

  it "FBK-004 unlinks a ride and recalculates at the FTP in force on its local date" do
    ride = unlinked_ride
    described_class.new(ride).link!(workout, origin: :automatic)
    before = history(workout)

    described_class.new(ride).unlink!

    expect(ride.reload).to have_attributes(planned_workout: nil, link_origin: nil, figures_ftp_watts: 250)
    expect(ride.intensity_factor.to_f).to be_within(1e-3).of(227.4 / 250)
    expect(history(workout)).to eq(before)
  end

  it "GAR-008 relinks a ride to another completed workout in one action" do
    ride = unlinked_ride
    described_class.new(ride).link!(workout, origin: :automatic)
    before = [ history(workout), history(other_workout) ]

    described_class.new(ride).link!(other_workout, origin: :rider)

    expect(ride.reload).to have_attributes(planned_workout: other_workout, link_origin: "rider", figures_ftp_watts: 260)
    expect(workout.reload.activity).to be_nil
    expect([ history(workout), history(other_workout) ]).to eq(before)
  end

  it "FBK-004 refuses a workout that already has a ride and leaves both unchanged" do
    linked = create(:activity, user: user, planned_workout: workout)
    ride = unlinked_ride

    expect { described_class.new(ride).link!(workout, origin: :rider) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(ride.reload.planned_workout).to be_nil
    expect(linked.reload.planned_workout).to eq(workout)
  end

  it "FBK-004 refuses another rider's workout" do
    ride = unlinked_ride
    someone_elses = create(:planned_workout, :completed)

    expect { described_class.new(ride).link!(someone_elses, origin: :rider) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(ride.reload.planned_workout).to be_nil
  end

  describe "FTP in force on the ride's date" do
    it "uses the newest reading on or before the date, highest id on a tie" do
      create(:ftp_reading, rider_profile: profile, ftp_watts: 255, effective_on: Date.new(2026, 8, 25))
      create(:ftp_reading, rider_profile: profile, ftp_watts: 245, effective_on: Date.new(2026, 8, 25))
      ride = unlinked_ride

      described_class.new(ride).recalculate!

      expect(ride.reload.figures_ftp_watts).to eq(245)
    end

    it "uses the earliest reading for a ride before the first" do
      profile.ftp_readings.where(effective_on: Date.new(2026, 8, 1)).update_all(effective_on: Date.new(2026, 8, 30))
      ride = unlinked_ride

      described_class.new(ride).recalculate!

      expect(ride.reload.figures_ftp_watts).to eq(250)
    end

    it "uses only the rider's own FTP history" do
      other_profile = create(:rider_profile, ftp_watts: 150)
      create(:ftp_reading, rider_profile: other_profile, ftp_watts: 150, effective_on: Date.new(2026, 8, 20))
      ride = unlinked_ride

      described_class.new(ride).recalculate!

      expect(ride.reload.figures_ftp_watts).to eq(250)
    end
  end

  it "keeps an activity without a stored file as it is" do
    run = create(:activity, :unlinked, user: user, source: :garmin, sport: :running, garmin_activity_id: 1, average_power_watts: nil, np_watts: nil, intensity_factor: nil, tss: nil, work_kj: nil)

    expect { described_class.new(run).recalculate! }.not_to change { run.reload.attributes }
  end
end
