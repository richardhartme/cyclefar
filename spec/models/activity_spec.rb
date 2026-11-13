require "rails_helper"

RSpec.describe Activity, type: :model do
  def completed_workout_for(user, scheduled_on: Date.new(2026, 9, 10))
    plan = user.training_plans.first || create(:training_plan, user: user)
    create(:planned_workout, :completed, training_plan: plan, scheduled_on: scheduled_on)
  end

  describe "ownership and links" do
    it "FBK-004 belongs to its rider and may stand alone without a workout" do
      activity = create(:activity, :unlinked)

      expect(activity).to be_persisted
      expect(activity.planned_workout).to be_nil
      expect(activity.link_origin).to be_nil
      expect(activity.user.activities).to eq([ activity ])
    end

    it "FBK-004 stores one activity per workout" do
      activity = create(:activity)
      duplicate = build(:activity, user: activity.user, planned_workout: activity.planned_workout)

      expect(duplicate).not_to be_valid
      expect_database_rejection(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
    end

    it "FBK-004 links only to completed workouts" do
      planned = create(:planned_workout, :structured)
      activity = build(:activity, user: planned.training_plan.user, planned_workout: planned)

      expect(activity).not_to be_valid
      expect(activity.errors[:planned_workout]).to include("must be completed")
      expect_database_rejection { activity.save!(validate: false) }
    end

    it "FBK-004 links only to the same rider's workouts" do
      activity = create(:activity, :unlinked)
      someone_elses = completed_workout_for(create(:user))

      activity.assign_attributes(planned_workout: someone_elses, link_origin: :rider)

      expect(activity).not_to be_valid
      expect(activity.errors[:planned_workout]).to include("must belong to the same rider")
      expect_database_rejection { described_class.where(id: activity.id).update_all(planned_workout_id: someone_elses.id, link_origin: "rider") }
    end

    it "FBK-004 may move to another completed workout of the same rider" do
      activity = create(:activity)
      other = completed_workout_for(activity.user, scheduled_on: Date.new(2026, 9, 12))

      activity.update!(planned_workout: other)

      expect(activity.reload.planned_workout).to eq(other)
    end

    it "FBK-004 records the link's origin exactly when linked" do
      expect(build(:activity, link_origin: nil)).not_to be_valid
      expect(build(:activity, :unlinked, link_origin: :rider)).not_to be_valid
      expect_database_rejection { build(:activity, link_origin: nil).save!(validate: false) }
      expect(build(:activity, link_origin: :automatic)).to be_linked_automatic
    end

    it "GAR-003 keeps Garmin activity ids unique per rider" do
      activity = create(:activity, :unlinked, source: :garmin, garmin_activity_id: 25_000_000_001)
      duplicate = build(:activity, :unlinked, user: activity.user, source: :garmin, garmin_activity_id: 25_000_000_001)

      expect(duplicate).not_to be_valid
      expect_database_rejection(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
      expect(build(:activity, :unlinked, source: :garmin, garmin_activity_id: 25_000_000_001)).to be_valid
    end

    it "keeps the activity when its workout row goes away" do
      activity = create(:activity)
      workout_id = activity.planned_workout_id

      # Completed workouts are never deleted; this exercises the foreign key's
      # safety net. Disabling triggers is transactional and rolls back.
      %w[planned_workouts workout_steps workout_feedbacks].each do |table|
        ActiveRecord::Base.connection.execute("ALTER TABLE #{table} DISABLE TRIGGER USER")
      end
      WorkoutStep.where(planned_workout_id: workout_id).delete_all
      WorkoutFeedback.where(planned_workout_id: workout_id).delete_all
      PlannedWorkout.where(id: workout_id).delete_all

      expect(activity.reload).to have_attributes(planned_workout_id: nil, link_origin: nil)
    end
  end

  it "records power metrics together or not at all" do
    expect(build(:activity, :without_power)).to be_valid
    expect(build(:activity, :without_power).power?).to be(false)

    partial = build(:activity, tss: nil)
    expect(partial).not_to be_valid
    expect_database_rejection { partial.save!(validate: false) }
  end

  it "rejects moving time longer than elapsed time and negative metrics" do
    longer = build(:activity, moving_seconds: 3661)
    expect(longer).not_to be_valid
    expect_database_rejection { longer.save!(validate: false) }

    negative = build(:activity, work_kj: -1)
    expect(negative).not_to be_valid
    expect_database_rejection { negative.save!(validate: false) }
  end

  it "requires a ride file for uploads, and stores files only for cycling" do
    upload = build(:activity)
    upload.ride_file.detach
    expect(upload).not_to be_valid

    run = build(:activity, :unlinked, source: :garmin, sport: :running, garmin_activity_id: 1)
    expect(run).to be_valid
    run.ride_file.attach(io: StringIO.new("run"), filename: "run.fit")
    expect(run).not_to be_valid
  end

  it "compares the local ride date with the scheduled date" do
    activity = build(:activity)
    scheduled = activity.planned_workout.scheduled_on
    expect(activity.date_mismatch?).to be(false)

    # 23:30 UTC on a British Summer Time date is already the next local day.
    activity.started_on = nil
    activity.assign_metrics(started_at: Time.utc(scheduled.year, scheduled.month, scheduled.day, 23, 30))
    expect(activity.ridden_on).to eq(scheduled + 1)
    expect(activity.date_mismatch?).to be(true)
  end

  it "FBK-004 can be changed, unlinked and removed while the completed workout stays immutable" do
    activity = create(:activity)
    workout = activity.planned_workout
    before = workout.reload.attributes

    activity.update!(tss: 50, intensity_factor: 0.7)
    activity.update!(planned_workout: nil, link_origin: nil)
    activity.destroy!

    expect(workout.reload.attributes).to eq(before)
    expect { workout.update!(name: "Changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
