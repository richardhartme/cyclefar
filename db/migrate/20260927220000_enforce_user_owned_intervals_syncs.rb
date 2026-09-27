class EnforceUserOwnedIntervalsSyncs < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE intervals_icu_syncs AS sync
      SET user_id = plan.user_id
      FROM planned_workouts AS workout
      JOIN training_plans AS plan ON plan.id = workout.training_plan_id
      WHERE sync.planned_workout_id = workout.id AND sync.user_id IS NULL
    SQL

    mismatched_links = select_value(<<~SQL).to_i
      SELECT COUNT(*) FROM intervals_icu_syncs AS sync
      JOIN planned_workouts AS workout ON workout.id = sync.planned_workout_id
      JOIN training_plans AS plan ON plan.id = workout.training_plan_id
      WHERE sync.user_id IS DISTINCT FROM plan.user_id
    SQL
    raise "Linked Intervals.icu sync owners disagree with their plans" if mismatched_links.positive?

    detached_without_owner = select_value("SELECT COUNT(*) FROM intervals_icu_syncs WHERE planned_workout_id IS NULL AND user_id IS NULL").to_i
    if detached_without_owner.positive?
      owner_id = explicit_legacy_owner_id
      execute "UPDATE intervals_icu_syncs SET user_id = #{owner_id} WHERE planned_workout_id IS NULL AND user_id IS NULL"
    end

    change_column_null :intervals_icu_syncs, :user_id, false
    add_foreign_key :intervals_icu_syncs, :users
    add_index :intervals_icu_syncs, :user_id
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Sync ownership must remain attached to detached remote events"
  end

  private

  def explicit_legacy_owner_id
    owner_id = Integer(ENV.fetch("CYCLEFAR_LEGACY_OWNER_USER_ID", ""), 10)
    raise ArgumentError unless owner_id.positive? && select_value("SELECT 1 FROM users WHERE id = #{owner_id}")

    owner_id
  rescue ArgumentError
    raise "An existing CYCLEFAR_LEGACY_OWNER_USER_ID is required for detached Intervals.icu sync records"
  end
end
