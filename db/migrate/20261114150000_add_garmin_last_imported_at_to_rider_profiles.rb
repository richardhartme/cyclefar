# ADR 0002 / GAR-003: when the last successful Garmin import started. The next
# import's window starts 7 days before it.
class AddGarminLastImportedAtToRiderProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :rider_profiles, :garmin_last_imported_at, :datetime
  end
end
