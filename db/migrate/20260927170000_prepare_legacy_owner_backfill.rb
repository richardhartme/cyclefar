class PrepareLegacyOwnerBackfill < ActiveRecord::Migration[8.1]
  def up
    backfill = LegacyOwnership::Backfill.new(connection: connection, owner_id: ENV["CYCLEFAR_LEGACY_OWNER_USER_ID"])
    say "Legacy counts: #{backfill.counts.map { |name, count| "#{name}=#{count}" }.join(', ')}"
    inventory = backfill.report
    say "Selected owner: #{inventory[:owner] || 'none'}"
    backfill.preflight!

    %i[rider_profiles training_plans intervals_icu_syncs].each do |table|
      add_column table, :user_id, :bigint unless column_exists?(table, :user_id)
    end
    backfill.backfill!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Restore the pre-cutover backup; removing ownership would lose the selected account"
  end
end
