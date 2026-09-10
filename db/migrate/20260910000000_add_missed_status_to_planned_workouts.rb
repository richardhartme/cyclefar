class AddMissedStatusToPlannedWorkouts < ActiveRecord::Migration[8.1]
  COMPLETION_SNAPSHOT_CONSTRAINT = <<~SQL.squish
    (status IN ('planned', 'missed') AND completed_at IS NULL AND completed_ftp_watts IS NULL AND completed_target_snapshot IS NULL)
    OR
    (status = 'completed' AND completed_at IS NOT NULL AND
      (kind = 'ftp_test' OR
        (detail_status = 'structured' AND completed_ftp_watts IS NOT NULL AND completed_ftp_watts > 0
          AND completed_target_snapshot IS NOT NULL AND jsonb_typeof(completed_target_snapshot) = 'object'
          AND completed_target_snapshot <> '{}'::jsonb)))
  SQL

  def up
    remove_check_constraint :planned_workouts, name: "planned_workouts_status_values"
    add_check_constraint :planned_workouts, "status IN ('planned', 'missed', 'completed')", name: "planned_workouts_status_values"

    remove_check_constraint :planned_workouts, name: "planned_workouts_completion_snapshot"
    add_check_constraint :planned_workouts, COMPLETION_SNAPSHOT_CONSTRAINT, name: "planned_workouts_completion_snapshot"
  end

  def down
    remove_check_constraint :planned_workouts, name: "planned_workouts_completion_snapshot"
    add_check_constraint :planned_workouts, <<~SQL.squish, name: "planned_workouts_completion_snapshot"
      (status = 'planned' AND completed_at IS NULL AND completed_ftp_watts IS NULL AND completed_target_snapshot IS NULL)
      OR
      (status = 'completed' AND completed_at IS NOT NULL AND
        (kind = 'ftp_test' OR
          (detail_status = 'structured' AND completed_ftp_watts IS NOT NULL AND completed_ftp_watts > 0
            AND completed_target_snapshot IS NOT NULL AND jsonb_typeof(completed_target_snapshot) = 'object'
            AND completed_target_snapshot <> '{}'::jsonb)))
    SQL

    remove_check_constraint :planned_workouts, name: "planned_workouts_status_values"
    add_check_constraint :planned_workouts, "status IN ('planned', 'completed')", name: "planned_workouts_status_values"
  end
end
