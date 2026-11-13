# ADR 0002: a ride becomes a rider-owned Activity that may link to one
# completed workout of the same rider, and can be relinked.
class ReplaceWorkoutActivitiesWithActivities < ActiveRecord::Migration[8.1]
  def up
    execute "DROP TRIGGER require_completed_workout_activity_parent ON workout_activities;"
    execute "DROP FUNCTION require_completed_workout_activity_parent();"

    rename_table :workout_activities, :activities
    execute "UPDATE active_storage_attachments SET record_type = 'Activity' WHERE record_type = 'WorkoutActivity';"
    %w[durations nonnegative_metrics power_metrics_together].each do |name|
      execute "ALTER TABLE activities RENAME CONSTRAINT workout_activities_#{name} TO activities_#{name};"
    end

    add_reference :activities, :user, foreign_key: true, index: false
    change_table :activities, bulk: true do |t|
      t.string :source
      t.bigint :garmin_activity_id
      t.string :sport
      t.string :external_type
      t.string :name
      t.date :started_on
      t.decimal :distance_metres, precision: 12, scale: 2
      t.jsonb :summary, null: false, default: {}
      t.string :link_origin
      t.integer :figures_ftp_watts
    end

    execute <<~SQL
      UPDATE activities
      SET user_id = training_plans.user_id,
          source = 'upload',
          sport = 'cycling',
          link_origin = 'rider',
          started_on = (activities.started_at AT TIME ZONE '#{Time.zone.tzinfo.identifier}')::date,
          figures_ftp_watts = planned_workouts.completed_ftp_watts
      FROM planned_workouts
      JOIN training_plans ON training_plans.id = planned_workouts.training_plan_id
      WHERE planned_workouts.id = activities.planned_workout_id;
    SQL

    change_column_null :activities, :user_id, false
    change_column_null :activities, :source, false
    change_column_null :activities, :sport, false
    change_column_null :activities, :started_on, false
    change_column_null :activities, :planned_workout_id, true

    add_index :activities, [ :user_id, :started_on ]
    add_index :activities, [ :user_id, :garmin_activity_id ], unique: true, where: "garmin_activity_id IS NOT NULL"
    remove_foreign_key :activities, :planned_workouts
    add_foreign_key :activities, :planned_workouts, on_delete: :nullify

    add_check_constraint :activities, "source IN ('upload', 'garmin')", name: "activities_source"
    add_check_constraint :activities, "sport IN ('cycling', 'running', 'walking', 'strength', 'yoga', 'swimming', 'other')", name: "activities_sport"
    add_check_constraint :activities,
      "(planned_workout_id IS NULL) = (link_origin IS NULL) AND (link_origin IS NULL OR link_origin IN ('automatic', 'rider'))",
      name: "activities_link_origin"
    add_check_constraint :activities, "distance_metres >= 0 AND figures_ftp_watts > 0", name: "activities_nonnegative_details"

    # Activities sit beside completed history without changing it, so the
    # completed-child guard does not apply. A link must point at a completed
    # workout in one of the same rider's plans; relinking is allowed. Clearing
    # the link, including the foreign key's ON DELETE SET NULL safety net,
    # clears its origin.
    execute <<~SQL
      CREATE FUNCTION require_completed_activity_link() RETURNS trigger AS $$
      DECLARE
        parent_status text;
        parent_user_id bigint;
      BEGIN
        IF NEW.planned_workout_id IS NULL THEN
          NEW.link_origin := NULL;
          RETURN NEW;
        END IF;
        IF TG_OP = 'UPDATE' AND NEW.planned_workout_id = OLD.planned_workout_id AND NEW.user_id = OLD.user_id THEN
          RETURN NEW;
        END IF;
        SELECT planned_workouts.status, training_plans.user_id INTO parent_status, parent_user_id
        FROM planned_workouts
        JOIN training_plans ON training_plans.id = planned_workouts.training_plan_id
        WHERE planned_workouts.id = NEW.planned_workout_id
        FOR SHARE OF planned_workouts;
        IF parent_status IS DISTINCT FROM 'completed' THEN
          RAISE EXCEPTION 'Activities link only to completed workouts' USING ERRCODE = '23514';
        END IF;
        IF parent_user_id IS DISTINCT FROM NEW.user_id THEN
          RAISE EXCEPTION 'Activities link only to the same rider''s workouts' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER require_completed_activity_link
      BEFORE INSERT OR UPDATE ON activities
      FOR EACH ROW EXECUTE FUNCTION require_completed_activity_link();
    SQL
  end

  def down
    if select_value("SELECT COUNT(*) FROM activities WHERE planned_workout_id IS NULL OR source <> 'upload'").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, "Unlinked or Garmin activities have no WorkoutActivity equivalent"
    end

    execute "DROP TRIGGER require_completed_activity_link ON activities;"
    execute "DROP FUNCTION require_completed_activity_link();"
    remove_check_constraint :activities, name: "activities_nonnegative_details"
    remove_check_constraint :activities, name: "activities_link_origin"
    remove_check_constraint :activities, name: "activities_sport"
    remove_check_constraint :activities, name: "activities_source"
    remove_foreign_key :activities, :planned_workouts
    add_foreign_key :activities, :planned_workouts
    remove_index :activities, [ :user_id, :garmin_activity_id ]
    remove_index :activities, [ :user_id, :started_on ]
    change_column_null :activities, :planned_workout_id, false
    change_table :activities, bulk: true do |t|
      t.remove :source, :garmin_activity_id, :sport, :external_type, :name, :started_on, :distance_metres, :summary, :link_origin, :figures_ftp_watts
    end
    remove_reference :activities, :user, foreign_key: true, index: false

    %w[durations nonnegative_metrics power_metrics_together].each do |name|
      execute "ALTER TABLE activities RENAME CONSTRAINT activities_#{name} TO workout_activities_#{name};"
    end
    execute "UPDATE active_storage_attachments SET record_type = 'WorkoutActivity' WHERE record_type = 'Activity';"
    rename_table :activities, :workout_activities

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
end
