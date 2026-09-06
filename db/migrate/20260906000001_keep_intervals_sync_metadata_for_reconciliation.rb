class KeepIntervalsSyncMetadataForReconciliation < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :intervals_icu_syncs, :planned_workouts
    change_column_null :intervals_icu_syncs, :planned_workout_id, true
    add_foreign_key :intervals_icu_syncs, :planned_workouts, on_delete: :nullify
  end
end
