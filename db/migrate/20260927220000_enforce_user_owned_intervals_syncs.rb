class EnforceUserOwnedIntervalsSyncs < ActiveRecord::Migration[8.1]
  def up
    change_column_null :intervals_icu_syncs, :user_id, false
    add_foreign_key :intervals_icu_syncs, :users
    add_index :intervals_icu_syncs, :user_id
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Sync ownership must remain attached to detached remote events"
  end
end
