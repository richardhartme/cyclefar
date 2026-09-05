require "rails_helper"

RSpec.describe PlannedWorkout, type: :model do
  it "WKO-006 enforces one workout per plan/date, including FTP tests" do
    workout = create(:planned_workout)
    duplicate = build(:planned_workout, :ftp_test, training_plan: workout.training_plan, scheduled_on: workout.scheduled_on)
    expect(duplicate).not_to be_valid
    expect_database_rejection(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
    expect(create(:planned_workout, training_plan: create(:training_plan, :archived), scheduled_on: workout.scheduled_on)).to be_persisted
  end

  it "rejects dates outside the plan and phases belonging to another plan" do
    workout = build(:planned_workout)
    workout.scheduled_on = workout.training_plan.starts_on - 1
    expect(workout).not_to be_valid
    workout.scheduled_on = workout.training_plan.starts_on
    workout.plan_phase = build(:plan_phase, training_plan: build(:training_plan, :archived))
    expect(workout).not_to be_valid
  end

  it "GEN-001 stores exact canonical structures only for structured workouts" do
    workout = build(:planned_workout, :structured)
    expect(workout).to be_valid
    workout.workout_steps.first.duration_seconds -= 30
    expect(workout).not_to be_valid
    workout.workout_steps.clear
    expect(workout).not_to be_valid
    expect(build(:planned_workout)).to be_valid
  end

  it "FTP-001 stores FTP tests with no invented protocol or metrics" do
    workout = create(:planned_workout, :ftp_test)
    expect(workout.workout_steps).to be_empty
    expect(workout.update(estimated_tss: 50)).to be(false)
    expect_database_rejection { workout.update_columns(estimated_tss: 50) }
  end

  it "FBK-001 requires a snapshot and timestamp before completion" do
    workout = create(:planned_workout, :structured)
    expect(workout.update(status: :completed)).to be(false)
    expect_database_rejection { workout.update_columns(status: "completed") }
  end

  describe "FBK-001 / SET-001 completed history" do
    let!(:workout) { create(:planned_workout, :completed) }

    it "prevents model edits and destruction" do
      expect { workout.update!(name: "Changed history") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(workout.destroy).to be(false)
      expect(workout.reload).to be_completed
    end

    it "prevents bulk edits, status reversal and deletion in PostgreSQL" do
      expect_database_rejection { described_class.where(id: workout.id).update_all(status: "planned") }
      expect_database_rejection { described_class.where(id: workout.id).update_all(scheduled_on: workout.scheduled_on + 1) }
      expect_database_rejection { described_class.where(id: workout.id).delete_all }
    end

    it "prevents step insertion, changes, deletion and reparenting" do
      step = workout.workout_steps.sole
      expect(step.update(target_low_pct_ftp: 50)).to be(false)
      expect(step.destroy).to be(false)
      expect(build(:workout_step, planned_workout: workout, position: 2)).not_to be_valid
      expect_database_rejection { step.update_columns(duration_seconds: 60) }
      expect_database_rejection { WorkoutStep.where(id: step.id).delete_all }
      expect_database_rejection { build(:workout_step, planned_workout: workout, position: 2).save!(validate: false) }
      other = create(:planned_workout, training_plan: workout.training_plan, scheduled_on: workout.scheduled_on + 1)
      expect_database_rejection { step.update_columns(planned_workout_id: other.id) }
    end

    it "preserves submitted feedback" do
      feedback = workout.workout_feedback
      expect(feedback.update(rpe: 9)).to be(false)
      expect(feedback.destroy).to be(false)
      expect_database_rejection { feedback.update_columns(rpe: 9) }
      expect_database_rejection { WorkoutFeedback.where(id: feedback.id).delete_all }
    end

    it "rejects writes from stale instances loaded before completion" do
      stale = described_class.find(workout.id)
      # Simulate a pre-completion instance without weakening the database guard.
      stale.status = "planned"
      stale.clear_changes_information
      expect_database_rejection { stale.update_columns(name: "Stale edit") }
      expect(workout.reload.name).to eq("Endurance 60 min")
    end

    it "rejects attaching an existing step or feedback to completed history" do
      other = create(:planned_workout, :structured, training_plan: workout.training_plan, scheduled_on: workout.scheduled_on + 1)
      step = other.workout_steps.sole
      expect_database_rejection { step.update_columns(planned_workout_id: workout.id, position: 2) }
      feedback = create(:workout_feedback, planned_workout: other)
      expect_database_rejection { feedback.update_columns(planned_workout_id: workout.id) }
    end

    it "retains structure, historical watts and metrics after Settings FTP changes" do
      original = workout.reload.attributes
      original_steps = workout.workout_steps.map(&:attributes)
      Settings::Update.new(profile: RiderProfile.current, attributes: { ftp_watts: 300 }).call
      expect(workout.reload.attributes).to eq(original)
      expect(workout.workout_steps.map(&:attributes)).to eq(original_steps)
    end

    it "PLN-014 retains the parent plan on attempted deletion, while allowing archival" do
      plan = workout.training_plan
      expect(plan.destroy).to be(false)
      expect_database_rejection(ActiveRecord::InvalidForeignKey) { TrainingPlan.where(id: plan.id).delete_all }
      plan.update!(status: :archived)
      expect(workout.reload.training_plan).to be_archived
    end

    it "allows independent sync metadata updates without touching completed history" do
      sync = create(:intervals_icu_sync, planned_workout: workout)
      expect(sync.update(intervals_event_id: 123, last_synced_at: Time.current)).to be(true)
    end
  end

  it "allows planned structure edits and destruction of plans without completed history" do
    workout = create(:planned_workout, :structured)
    expect(workout.workout_steps.sole.update(target_low_pct_ftp: 62)).to be(true)
    plan = workout.training_plan
    plan.destroy!
    expect(described_class.exists?(workout.id)).to be(false)
    expect(WorkoutStep.count).to eq(0)
  end
end
