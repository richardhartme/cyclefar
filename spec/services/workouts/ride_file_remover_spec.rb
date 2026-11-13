require "rails_helper"

RSpec.describe Workouts::RideFileRemover, type: :service do
  it "removes the ride file and metrics but keeps completed history" do
    activity = create(:activity)
    workout = activity.planned_workout
    before = [ workout.reload.attributes, workout.workout_feedback.attributes ]

    described_class.new(workout).call

    expect(Activity.exists?(activity.id)).to be(false)
    expect(ActiveStorage::Attachment.where(record: activity).count).to eq(0)
    expect([ workout.reload.attributes, workout.workout_feedback.attributes ]).to eq(before)
  end

  it "GAR-008 unlinks a Garmin ride and keeps it" do
    workout = create(:planned_workout, :completed)
    create(:rider_profile, user: workout.training_plan.user)
    activity = create(:activity, :unlinked, user: workout.training_plan.user, source: :garmin, garmin_activity_id: 1)
    activity.ride_file.attach(io: file_fixture("fit/outdoor_ride.fit").open, filename: "garmin.fit")
    Activities::Linker.new(activity).link!(workout, origin: :automatic)

    described_class.new(workout).call

    expect(activity.reload).to have_attributes(planned_workout: nil, link_origin: nil)
    expect(activity.ride_file).to be_attached
  end

  it "does nothing when no ride file is attached" do
    workout = create(:planned_workout, :completed)

    expect { described_class.new(workout).call }.not_to change(Activity, :count)
  end
end
