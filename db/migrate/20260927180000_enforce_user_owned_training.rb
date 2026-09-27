class EnforceUserOwnedTraining < ActiveRecord::Migration[8.1]
  def up
    LegacyOwnership::Backfill.new(connection: connection, owner_id: ENV["CYCLEFAR_LEGACY_OWNER_USER_ID"]).backfill!

    change_column_null :rider_profiles, :user_id, false
    add_foreign_key :rider_profiles, :users
    add_index :rider_profiles, :user_id, unique: true
    remove_check_constraint :rider_profiles, name: "rider_profiles_singleton"

    change_column_null :training_plans, :user_id, false
    add_foreign_key :training_plans, :users
    add_index :training_plans, :user_id, unique: true, where: "status = 'active'", name: "one_active_training_plan_per_user"
    remove_index :training_plans, name: "one_active_training_plan"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Multiple owners cannot be returned to singleton training data"
  end
end
