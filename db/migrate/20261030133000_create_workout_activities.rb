class CreateWorkoutActivities < ActiveRecord::Migration[8.1]
  def up
    create_table :workout_activities do |t|
      t.references :planned_workout, null: false, foreign_key: true, index: { unique: true }
      t.datetime :started_at, null: false
      t.integer :elapsed_seconds, null: false
      t.integer :moving_seconds, null: false
      t.decimal :average_power_watts, precision: 12, scale: 4
      t.decimal :np_watts, precision: 12, scale: 4
      t.decimal :intensity_factor, precision: 8, scale: 5
      t.decimal :tss, precision: 12, scale: 4
      t.decimal :work_kj, precision: 14, scale: 4
      t.decimal :average_heart_rate_bpm, precision: 6, scale: 2
      t.timestamps

      t.check_constraint "elapsed_seconds >= 0 AND moving_seconds >= 0 AND moving_seconds <= elapsed_seconds", name: "workout_activities_durations"
      t.check_constraint "average_power_watts >= 0 AND np_watts >= 0 AND intensity_factor >= 0 AND tss >= 0 AND work_kj >= 0 AND average_heart_rate_bpm > 0",
        name: "workout_activities_nonnegative_metrics"
      t.check_constraint <<~SQL.squish, name: "workout_activities_power_metrics_together"
        (average_power_watts IS NULL AND np_watts IS NULL AND intensity_factor IS NULL AND tss IS NULL AND work_kj IS NULL)
        OR (average_power_watts IS NOT NULL AND np_watts IS NOT NULL AND intensity_factor IS NOT NULL AND tss IS NOT NULL AND work_kj IS NOT NULL)
      SQL
    end

    # Ridden metrics sit beside completed history without changing it, so the
    # completed-child guard does not apply. Rides attach only to completed
    # workouts and never move between workouts.
    execute <<~SQL
      CREATE FUNCTION require_completed_workout_activity_parent() RETURNS trigger AS $$
      DECLARE
        parent_status text;
      BEGIN
        IF TG_OP = 'UPDATE' AND NEW.planned_workout_id != OLD.planned_workout_id THEN
          RAISE EXCEPTION 'Ride files cannot move between workouts' USING ERRCODE = '23514';
        END IF;
        SELECT status INTO parent_status FROM planned_workouts WHERE id = NEW.planned_workout_id FOR SHARE;
        IF parent_status IS DISTINCT FROM 'completed' THEN
          RAISE EXCEPTION 'Ride files attach only to completed workouts' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER require_completed_workout_activity_parent
      BEFORE INSERT OR UPDATE ON workout_activities
      FOR EACH ROW EXECUTE FUNCTION require_completed_workout_activity_parent();
    SQL
  end

  def down
    drop_table :workout_activities
    execute "DROP FUNCTION require_completed_workout_activity_parent();"
  end
end
