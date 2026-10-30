require "rails_helper"

RSpec.describe WorkoutActivity, type: :model do
  it "stores one ride per completed workout" do
    activity = create(:workout_activity)
    duplicate = build(:workout_activity, planned_workout: activity.planned_workout)

    expect(duplicate).not_to be_valid
    expect_database_rejection(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  it "attaches only to completed workouts" do
    planned = create(:planned_workout, :structured)
    activity = build(:workout_activity, planned_workout: planned)

    expect(activity).not_to be_valid
    expect(activity.errors[:planned_workout]).to include("must be completed")
    expect_database_rejection { activity.save!(validate: false) }
  end

  it "never moves between workouts" do
    activity = create(:workout_activity)
    other = create(:planned_workout, :completed, training_plan: activity.planned_workout.training_plan, scheduled_on: activity.planned_workout.scheduled_on + 1)

    expect { activity.update_columns(planned_workout_id: other.id) }.to raise_error(ActiveRecord::ActiveRecordError)
    expect_database_rejection { described_class.where(id: activity.id).update_all(planned_workout_id: other.id) }
  end

  it "records power metrics together or not at all" do
    expect(build(:workout_activity, :without_power)).to be_valid
    expect(build(:workout_activity, :without_power).power?).to be(false)

    partial = build(:workout_activity, tss: nil)
    expect(partial).not_to be_valid
    expect_database_rejection { partial.save!(validate: false) }
  end

  it "rejects moving time longer than elapsed time and negative metrics" do
    longer = build(:workout_activity, moving_seconds: 3661)
    expect(longer).not_to be_valid
    expect_database_rejection { longer.save!(validate: false) }

    negative = build(:workout_activity, work_kj: -1)
    expect(negative).not_to be_valid
    expect_database_rejection { negative.save!(validate: false) }
  end

  it "requires a ride file" do
    activity = build(:workout_activity)
    activity.ride_file.detach

    expect(activity).not_to be_valid
  end

  it "compares the local ride date with the scheduled date" do
    activity = build(:workout_activity)
    scheduled = activity.planned_workout.scheduled_on
    expect(activity.date_mismatch?).to be(false)

    # 23:30 UTC on a British Summer Time date is already the next local day.
    activity.started_at = Time.utc(scheduled.year, scheduled.month, scheduled.day, 23, 30)
    expect(activity.ridden_on).to eq(scheduled + 1)
    expect(activity.date_mismatch?).to be(true)
  end

  it "can be replaced and removed while the completed workout stays immutable" do
    activity = create(:workout_activity)
    workout = activity.planned_workout

    activity.update!(tss: 50, intensity_factor: 0.7)
    activity.destroy!

    expect(workout.reload).to be_completed
    expect { workout.update!(name: "Changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
