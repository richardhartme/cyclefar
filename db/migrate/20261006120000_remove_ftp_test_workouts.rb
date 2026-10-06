class RemoveFtpTestWorkouts < ActiveRecord::Migration[8.1]
  def up
    # CYF-77 explicitly includes completed FTP tests in this one-time cleanup.
    # The migration transaction and table locks keep the temporary exception
    # isolated; normal completed workouts and their children remain unchanged.
    execute <<~SQL
      LOCK TABLE planned_workouts, workout_steps, workout_feedbacks IN ACCESS EXCLUSIVE MODE;
      ALTER TABLE planned_workouts DISABLE TRIGGER protect_completed_workout;
      ALTER TABLE workout_steps DISABLE TRIGGER protect_completed_workout_steps;
      ALTER TABLE workout_feedbacks DISABLE TRIGGER protect_completed_workout_feedback;

      DELETE FROM workout_steps WHERE planned_workout_id IN (SELECT id FROM planned_workouts WHERE kind = 'ftp_test');
      DELETE FROM workout_feedbacks WHERE planned_workout_id IN (SELECT id FROM planned_workouts WHERE kind = 'ftp_test');
      DELETE FROM planned_workouts WHERE kind = 'ftp_test';

      ALTER TABLE workout_feedbacks ENABLE TRIGGER protect_completed_workout_feedback;
      ALTER TABLE workout_steps ENABLE TRIGGER protect_completed_workout_steps;
      ALTER TABLE planned_workouts ENABLE TRIGGER protect_completed_workout;
    SQL
    # The sync foreign key nullifies deleted identities so their owner can
    # reconcile any remote events on the next explicit sync.
    remove_check_constraint :planned_workouts, name: "planned_workouts_ftp_test_no_protocol"
    remove_check_constraint :planned_workouts, name: "planned_workouts_kind_values"
    add_check_constraint :planned_workouts, "kind IN ('workout', 'opener')", name: "planned_workouts_kind_values"
    remove_check_constraint :planned_workouts, name: "planned_workouts_minimum_duration"
    add_check_constraint :planned_workouts, "duration_minutes IS NOT NULL AND duration_minutes >= 30 AND intent IS NOT NULL", name: "planned_workouts_minimum_duration"
    remove_check_constraint :planned_workouts, name: "planned_workouts_completion_snapshot"
    add_check_constraint :planned_workouts, <<~SQL.squish, name: "planned_workouts_completion_snapshot"
      (status IN ('planned', 'missed') AND completed_at IS NULL AND completed_ftp_watts IS NULL AND completed_target_snapshot IS NULL)
      OR
      (status = 'completed' AND completed_at IS NOT NULL AND detail_status = 'structured'
        AND completed_ftp_watts IS NOT NULL AND completed_ftp_watts > 0
        AND completed_target_snapshot IS NOT NULL AND jsonb_typeof(completed_target_snapshot) = 'object'
        AND completed_target_snapshot <> '{}'::jsonb)
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Removed FTP-test records cannot be restored"
  end
end
