class ProtectCompletedWorkoutHistory < ActiveRecord::Migration[8.1]
  def up
    # Database guards cover bulk writes, stale model instances and dependent deletes.
    execute <<~SQL
      CREATE FUNCTION protect_completed_workout() RETURNS trigger AS $$
      BEGIN
        IF OLD.status = 'completed' THEN
          RAISE EXCEPTION 'Completed workouts are immutable' USING ERRCODE = '23514';
        END IF;
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER protect_completed_workout
      BEFORE UPDATE OR DELETE ON planned_workouts
      FOR EACH ROW EXECUTE FUNCTION protect_completed_workout();

      CREATE FUNCTION protect_completed_workout_child() RETURNS trigger AS $$
      DECLARE
        parent_id bigint;
        parent_status text;
      BEGIN
        -- Lock both old and new parents when reparenting. This serializes edits
        -- against completion so no child can slip into an immutable snapshot.
        FOR parent_id IN
          SELECT DISTINCT value FROM unnest(ARRAY[
            CASE WHEN TG_OP != 'INSERT' THEN OLD.planned_workout_id END,
            CASE WHEN TG_OP != 'DELETE' THEN NEW.planned_workout_id END
          ]) AS value WHERE value IS NOT NULL ORDER BY value
        LOOP
          SELECT status INTO parent_status FROM planned_workouts WHERE id = parent_id FOR UPDATE;
          IF parent_status = 'completed' THEN
            RAISE EXCEPTION 'Completed workout structure and feedback are immutable' USING ERRCODE = '23514';
          END IF;
        END LOOP;
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER protect_completed_workout_steps
      BEFORE INSERT OR UPDATE OR DELETE ON workout_steps
      FOR EACH ROW EXECUTE FUNCTION protect_completed_workout_child();

      CREATE TRIGGER protect_completed_workout_feedback
      BEFORE INSERT OR UPDATE OR DELETE ON workout_feedbacks
      FOR EACH ROW EXECUTE FUNCTION protect_completed_workout_child();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER protect_completed_workout_feedback ON workout_feedbacks;
      DROP TRIGGER protect_completed_workout_steps ON workout_steps;
      DROP TRIGGER protect_completed_workout ON planned_workouts;
      DROP FUNCTION protect_completed_workout_child();
      DROP FUNCTION protect_completed_workout();
    SQL
  end
end
