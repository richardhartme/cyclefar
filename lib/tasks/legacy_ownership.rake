namespace :legacy_ownership do
  desc "Read-only preflight for the explicit-owner legacy migration"
  task preflight: :environment do
    backfill = LegacyOwnership::Backfill.new(
      connection: ActiveRecord::Base.connection,
      owner_id: ENV["CYCLEFAR_LEGACY_OWNER_USER_ID"]
    )
    backfill.counts.each { |name, count| puts "#{name}: #{count}" }
    inventory = backfill.report
    puts "selected_owner: #{inventory[:owner] || 'none'}"
    backfill.preflight!
    puts "preflight: safe"
  end

  desc "Repeat the explicit-owner backfill after writes stop and before CYF-68 constraints"
  task backfill: :environment do
    backfill = LegacyOwnership::Backfill.new(
      connection: ActiveRecord::Base.connection,
      owner_id: ENV["CYCLEFAR_LEGACY_OWNER_USER_ID"]
    )
    backfill.counts.each { |name, count| puts "#{name}: #{count}" }
    puts "selected_owner: #{backfill.report[:owner] || 'none'}"
    backfill.backfill!
    puts "backfill: complete"
  end
end
