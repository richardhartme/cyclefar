require "rails_helper"

RSpec.describe Workouts::RideFileRemover, type: :service do
  it "removes the ride file and metrics but keeps completed history" do
    activity = create(:workout_activity)
    workout = activity.planned_workout
    before = [ workout.reload.attributes, workout.workout_feedback.attributes ]

    described_class.new(workout).call

    expect(WorkoutActivity.exists?(activity.id)).to be(false)
    expect(ActiveStorage::Attachment.where(record: activity).count).to eq(0)
    expect([ workout.reload.attributes, workout.workout_feedback.attributes ]).to eq(before)
  end

  it "does nothing when no ride file is attached" do
    workout = create(:planned_workout, :completed)

    expect { described_class.new(workout).call }.not_to change(WorkoutActivity, :count)
  end
end
