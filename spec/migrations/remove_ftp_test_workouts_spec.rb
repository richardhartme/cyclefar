require "rails_helper"
require Rails.root.join("db/migrate/20261006120000_remove_ftp_test_workouts")
require Rails.root.join("db/migrate/20260910000000_add_missed_status_to_planned_workouts")

RSpec.describe RemoveFtpTestWorkouts do
  let(:connection) { ActiveRecord::Base.connection }

  before do
    # Recreate the pre-removal schema inside the example's rollback transaction.
    %w[kind_values minimum_duration completion_snapshot].each do |suffix|
      connection.remove_check_constraint :planned_workouts, name: "planned_workouts_#{suffix}"
    end
    connection.add_check_constraint :planned_workouts, "kind IN ('workout', 'ftp_test', 'opener')", name: "planned_workouts_kind_values"
    connection.add_check_constraint :planned_workouts, "kind = 'ftp_test' OR (duration_minutes IS NOT NULL AND duration_minutes >= 30 AND intent IS NOT NULL)", name: "planned_workouts_minimum_duration"
    connection.add_check_constraint :planned_workouts, AddMissedStatusToPlannedWorkouts::COMPLETION_SNAPSHOT_CONSTRAINT, name: "planned_workouts_completion_snapshot"
    connection.add_check_constraint :planned_workouts,
      "kind != 'ftp_test' OR (estimated_np_watts IS NULL AND estimated_if IS NULL AND estimated_tss IS NULL AND estimated_work_kj IS NULL AND duration_minutes IS NULL AND detail_status = 'outline')",
      name: "planned_workouts_ftp_test_no_protocol"
  end

  def legacy_test(plan, date, status)
    id = PlannedWorkout.insert_all!([ { training_plan_id: plan.id, scheduled_on: date, kind: "ftp_test", status: "planned", name: "FTP Test" } ]).rows.sole.sole
    # Old database constraints permitted child records even though the model
    # rejected test protocols. Cleanup must handle those rows as well.
    create(:workout_step, planned_workout_id: id)
    WorkoutFeedback.insert_all!([ { planned_workout_id: id, rpe: 5, completion_quality: "as_planned" } ])
    attributes = { status: status }
    attributes[:completed_at] = Time.current if status == "completed"
    PlannedWorkout.where(id: id).update_all(attributes)
    id
  end

  it "CYF-77 deletes all FTP tests without rebuilding plans or changing ordinary completed history" do
    plan = create(:training_plan)
    archived = create(:training_plan, :archived)
    ordinary = create(:planned_workout, :completed, training_plan: plan)
    future = create(:planned_workout, training_plan: plan, scheduled_on: plan.starts_on + 7)
    opener = create(:planned_workout, kind: :opener, training_plan: archived)
    snapshot = [ ordinary.attributes, ordinary.workout_steps.map(&:attributes), ordinary.workout_feedback.attributes ]
    retained = [ plan, archived, future, opener ].map(&:attributes)
    ids = %w[planned missed completed].each_with_index.map do |status, index|
      legacy_test(index == 2 ? archived : plan, plan.starts_on + index + 2, status)
    end
    sync = IntervalsIcuSync.create!(user: archived.user, planned_workout_id: ids.last, external_id: "cyclefar-workout-#{ids.last}")
    identity = sync.attributes.except("planned_workout_id")

    ActiveRecord::Migration.suppress_messages { described_class.new.up }

    expect(PlannedWorkout.where(kind: "ftp_test")).not_to exist
    expect(WorkoutStep.where(planned_workout_id: ids)).not_to exist
    expect(WorkoutFeedback.where(planned_workout_id: ids)).not_to exist
    expect([ ordinary.reload.attributes, ordinary.workout_steps.reload.map(&:attributes), ordinary.workout_feedback.reload.attributes ]).to eq(snapshot)
    expect([ plan, archived, future, opener ].map { |record| record.reload.attributes }).to eq(retained)
    expect(sync.reload.planned_workout_id).to be_nil
    expect(sync.attributes.except("planned_workout_id")).to eq(identity)

    # The one-time cleanup exception must not weaken any ongoing history guard.
    expect_database_rejection { PlannedWorkout.where(id: ordinary.id).delete_all }
    expect_database_rejection { WorkoutStep.where(planned_workout_id: ordinary.id).delete_all }
    expect_database_rejection { WorkoutFeedback.where(planned_workout_id: ordinary.id).delete_all }
    expect_database_rejection { future.update_columns(kind: "ftp_test") }
    expect_database_rejection { future.update_columns(duration_minutes: nil) }
    expect_database_rejection { future.update_columns(status: "completed", completed_at: Time.current) }
  end
end
