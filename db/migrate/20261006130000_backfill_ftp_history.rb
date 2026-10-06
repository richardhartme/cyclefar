class BackfillFtpHistory < ActiveRecord::Migration[8.1]
  def up
    # Profiles created outside Settings (including demo data) may lack history.
    execute <<~SQL
      INSERT INTO ftp_readings (rider_profile_id, ftp_watts, effective_on, created_at, updated_at)
      SELECT id, ftp_watts,
        (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/London')::date,
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM rider_profiles
      WHERE NOT EXISTS (
        SELECT 1 FROM ftp_readings WHERE rider_profile_id = rider_profiles.id
      )
    SQL
    add_index :ftp_readings, [ :rider_profile_id, :effective_on, :id ], name: "index_ftp_readings_on_profile_and_recency"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Backfilled readings may have been edited by their owners"
  end
end
