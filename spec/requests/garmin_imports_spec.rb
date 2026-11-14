require "rails_helper"

RSpec.describe "Garmin import", type: :request do
  let(:garmin_rider) { create(:user, email_address: "garmin@example.com") }
  let!(:profile) do
    create(:rider_profile, user: garmin_rider, garmin_api_key: "garmin-key", garmin_api_key_expires_on: Date.new(2027, 5, 1))
  end
  let!(:plan) { create(:training_plan, user: garmin_rider) }
  let(:client) { instance_double(GarminConnect::Client) }
  let(:today) { Date.new(2026, 11, 14) }

  around do |example|
    travel_to(today.in_time_zone.change(hour: 9)) { with_garmin_rider_email("garmin@example.com") { example.run } }
  end

  before do
    allow(GarminConnect::Client).to receive(:new).with(api_key: "garmin-key").and_return(client)
  end

  def yoga(id)
    GarminConnect::ActivitySummary.from_payload(
      "activityId" => id,
      "activityName" => "Yoga",
      "activityType" => { "typeId" => 163, "typeKey" => "yoga", "parentTypeId" => 29 },
      "startTimeGMT" => "2026-11-10 18:00:00",
      "startTimeLocal" => "2026-11-10 18:00:00",
      "duration" => 1800.0)
  end

  describe "GAR-003 for the Garmin rider" do
    before { sign_in_as(garmin_rider) }

    it "shows Import from Garmin next to the Intervals.icu sync, with the key's expiry warning" do
      profile.update!(garmin_api_key_expires_on: today + 10)

      get root_path

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("form[action='#{garmin_import_path}'] button").text).to eq("Import from Garmin")
      expect(page.at_css("form[action='#{intervals_icu_sync_path}']")).to be_present
      expect(page.at_css("[role='alert']").text).to include("Your Garmin key expires on")
    end

    it "hides the button without a saved key" do
      profile.update!(garmin_api_key: nil, garmin_api_key_expires_on: nil)

      get root_path

      expect(response.body).to include("Sync workouts to Intervals.icu")
      expect(response.body).not_to include("Import from Garmin")
    end

    it "imports and reports the counts" do
      stale = create(:activity, :unlinked, user: garmin_rider, source: :garmin, sport: :yoga, garmin_activity_id: 7, started_on: Date.new(2026, 11, 1))
      allow(client).to receive(:activities).with(from: plan.starts_on, to: today).and_return([ yoga(1), yoga(2) ])

      post garmin_import_path

      expect(response).to redirect_to(root_path)
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq("Imported 2, updated 0, removed 1.")
      expect(garmin_rider.activities.pluck(:garmin_activity_id)).to contain_exactly(1, 2)
      expect(Activity.exists?(stale.id)).to be(false)
    end

    [
      [ GarminConnect::Client::AuthenticationError.new, "Your Garmin key was rejected or has expired. Update it in Settings." ],
      [ GarminConnect::Client::RateLimitedError.new(retry_after: 90), "Garmin is rate limiting requests. Try again in 2 minutes." ],
      [ GarminConnect::Client::RemoteError.new, "Garmin Connect is unavailable. Try again later." ]
    ].each do |error, message|
      it "explains a #{error.class.name.demodulize}" do
        allow(client).to receive(:activities).and_raise(error)

        post garmin_import_path

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(message)
      end
    end

    it "explains an activity CycleFar can't store instead of failing the request" do
      allow(client).to receive(:activities).and_return([ yoga(1) ])
      allow_any_instance_of(Activity).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(Activity.new))

      post garmin_import_path

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to start_with("Garmin import stopped:")
    end

    it "explains a missing key without calling Garmin" do
      profile.update!(garmin_api_key: nil, garmin_api_key_expires_on: nil)

      post garmin_import_path

      expect(flash[:alert]).to eq("Save a Garmin key in Settings before importing.")
      expect(GarminConnect::Client).not_to have_received(:new)
    end
  end

  describe "GAR-001 for anyone else" do
    let(:other_rider) { create(:user) }

    before do
      create(:rider_profile, user: other_rider)
      create(:training_plan, user: other_rider)
      sign_in_as(other_rider)
    end

    it "shows no import button and 404s the import route" do
      get root_path
      expect(response.body).not_to include("Import from Garmin")

      post garmin_import_path

      expect(response).to have_http_status(:not_found)
      expect(GarminConnect::Client).not_to have_received(:new)
    end
  end
end
