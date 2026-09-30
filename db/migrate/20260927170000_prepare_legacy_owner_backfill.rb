class PrepareLegacyOwnerBackfill < ActiveRecord::Migration[8.1]
  def up
    %i[rider_profiles training_plans intervals_icu_syncs].each do |table|
      add_column table, :user_id, :bigint unless column_exists?(table, :user_id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Removing ownership would discard the owning account"
  end
end
