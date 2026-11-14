# ADR 0002 / GAR-002: the Garmin rider's Personal API key, encrypted by the
# model, and the expiry date the rider enters because Garmin doesn't return it.
class AddGarminApiKeyToRiderProfiles < ActiveRecord::Migration[8.1]
  def change
    change_table :rider_profiles, bulk: true do |t|
      t.text :garmin_api_key
      t.date :garmin_api_key_expires_on
      t.check_constraint "garmin_api_key IS NULL OR garmin_api_key_expires_on IS NOT NULL", name: "rider_profiles_garmin_key_expiry"
    end
  end
end
