require "rails_helper"

RSpec.describe "Garmin key settings", type: :request do
  let(:garmin_rider) { create(:user, email_address: "garmin@example.com") }
  let!(:profile) { create(:rider_profile, user: garmin_rider) }
  let(:today) { Date.new(2026, 11, 14) }

  around do |example|
    travel_to(today.in_time_zone.change(hour: 9)) { with_garmin_rider_email("garmin@example.com") { example.run } }
  end

  def save_key(key: "garmin-personal-key", expires_on: "2027-05-01")
    patch garmin_key_path, params: { garmin_key: { garmin_api_key: key, garmin_api_key_expires_on: expires_on } }
  end

  describe "GAR-002 for the Garmin rider" do
    before { sign_in_as(garmin_rider) }

    it "saves the key and its expiry, encrypted, and only ever shows it masked" do
      save_key

      expect(response).to redirect_to(settings_path)
      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(response.body).to include("Garmin key saved.", "Saved Garmin key: ••••••••", "1 May 2027")
      expect(response.body).not_to include("garmin-personal-key")
      expect(profile.reload).to have_attributes(garmin_api_key: "garmin-personal-key", garmin_api_key_expires_on: Date.new(2027, 5, 1))
      stored = RiderProfile.connection.select_value("SELECT garmin_api_key FROM rider_profiles WHERE id = #{profile.id}")
      expect(stored).to be_present
      expect(stored).not_to include("garmin-personal-key")
    end

    it "rejects a key without an expiry date and never shows the submitted key" do
      save_key(key: "unsaved-garmin-key", expires_on: "")

      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(response.body).to include("Garmin key not saved: Garmin key expiry date can&#39;t be blank.")
      expect(response.body).not_to include("unsaved-garmin-key", "Saved Garmin key")
      expect(profile.reload.garmin_api_key).to be_nil
    end

    it "requires a key the first time, then keeps the saved key when the field is left blank" do
      save_key(key: "", expires_on: "2027-05-01")
      follow_redirect!
      expect(response.body).to include("Garmin key not saved: Garmin API key can&#39;t be blank.")
      expect(profile.reload.garmin_api_key_expires_on).to be_nil

      save_key
      save_key(key: "", expires_on: "2027-06-30")

      expect(profile.reload).to have_attributes(garmin_api_key: "garmin-personal-key", garmin_api_key_expires_on: Date.new(2027, 6, 30))

      save_key(key: "", expires_on: "")
      follow_redirect!
      expect(response.body).to include("Garmin key not saved: Garmin key expiry date can&#39;t be blank.")
      expect(profile.reload.garmin_api_key_expires_on).to eq(Date.new(2027, 6, 30))
    end

    it "removes the key and its expiry, keeping imported activities" do
      save_key
      activity = create(:activity, :unlinked, user: garmin_rider, source: :garmin, garmin_activity_id: 25_012_345_678)

      delete garmin_key_path

      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(response.body).to include("Garmin key removed. Imported activities are kept.")
      expect(response.body).not_to include("Saved Garmin key")
      expect(profile.reload).to have_attributes(garmin_api_key: nil, garmin_api_key_expires_on: nil)
      expect(Activity.find(activity.id)).to be_garmin
    end

    it "filters the key from request and SQL logs" do
      output = StringIO.new
      logger = ActiveSupport::Logger.new(output)
      original_loggers = [ Rails.logger, ActiveRecord::Base.logger ]
      Rails.logger = ActiveRecord::Base.logger = logger

      save_key(key: "never-log-this-garmin-key")

      expect(response).to have_http_status(:see_other)
      expect(output.string).to include("[FILTERED]")
      expect(output.string).not_to include("never-log-this-garmin-key")
    ensure
      Rails.logger, ActiveRecord::Base.logger = original_loggers
    end

    it "warns from 14 days before expiry and alerts once the key has expired" do
      warnings = { 15 => nil, 14 => "Your Garmin key expires on 28 Nov 2026.", 0 => "Your Garmin key expires on 14 Nov 2026.", -1 => "Your Garmin key expired on 13 Nov 2026." }

      warnings.each do |days, warning|
        profile.update!(garmin_api_key: "garmin-personal-key", garmin_api_key_expires_on: today + days)
        get settings_path
        expect(response.body).to include(days.negative? ? "Saved Garmin key: •••••••• · expired" : "Saved Garmin key: •••••••• · expires"), "#{days} days"
        alert = Nokogiri::HTML(response.body).at_css("#garmin-heading ~ [role=alert]")&.text&.squish

        if warning
          expect(alert).to eq("#{warning} Create a new key in the Garmin Connect Developer Program and save it in Settings."), "#{days} days"
        else
          expect(alert).to be_nil, "#{days} days"
        end
      end
    end

    it "asks for a saved FTP before a key can be added" do
      profile.ftp_readings.delete_all
      profile.destroy!

      get settings_path
      expect(response.body).to include("Save your FTP above before adding a Garmin key.")
      save_key
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GAR-001 for everyone else" do
    def expect_no_garmin_access(user)
      sign_in_as(user)

      get settings_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Garmin")

      save_key
      expect(response).to have_http_status(:not_found)
      delete garmin_key_path
      expect(response).to have_http_status(:not_found)
      expect(RiderProfile.where.not(garmin_api_key: nil)).to be_empty
    end

    it "shows another rider no Garmin UI and 404s the Garmin routes" do
      other = create(:user, email_address: "other@example.com")
      create(:rider_profile, user: other)

      expect_no_garmin_access(other)
    end

    it "shows no Garmin UI and 404s the Garmin routes when GARMIN_RIDER_EMAIL is unset" do
      with_garmin_rider_email(nil) { expect_no_garmin_access(garmin_rider) }
    end
  end
end
