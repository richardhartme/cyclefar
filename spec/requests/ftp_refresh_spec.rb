require "rails_helper"

RSpec.describe "FTP changes refresh Intervals.icu", type: :request do
  let(:user) { create(:user) }
  let!(:profile) { create(:rider_profile, user: user, ftp_watts: 260, intervals_icu_api_key: "test-key") }
  let!(:reading) { create(:ftp_reading, rider_profile: profile, ftp_watts: 260, effective_on: Date.current - 2) }
  let!(:plan) { create(:training_plan, user: user) }
  let!(:workout) { create(:planned_workout, :structured, training_plan: plan, scheduled_on: Date.current) }
  let!(:sync) { create(:intervals_icu_sync, planned_workout: workout, intervals_event_id: 100, last_synced_at: 1.day.ago) }
  let(:client) { instance_double(IntervalsIcu::Client) }

  before do
    sign_in_as(user)
    allow(IntervalsIcu::Client).to receive(:new).with(api_key: "test-key").and_return(client)
    allow(client).to receive(:upsert_events) do |events|
      events.map { |event| { "id" => 100, "external_id" => event[:external_id] } }
    end
  end

  it "CYF-83 saves a new FTP and reports the confirmed refresh count" do
    patch settings_path, params: { rider_profile: { ftp_watts: 300 } }
    expect(response).to have_http_status(:see_other)
    follow_redirect!
    expect(response.body).to include("Settings saved. Refreshed 1 workout in Intervals.icu.")
    expect(profile.reload.ftp_watts).to eq(300)
    expect(sync.reload.intervals_event_id).to eq(100)
  end

  it "CYF-83 reports refresh results for history edits and deletion fallback" do
    older = create(:ftp_reading, rider_profile: profile, ftp_watts: 250, effective_on: Date.current - 10)
    patch ftp_reading_path(reading), params: { ftp_reading: { ftp_watts: 280 } }
    follow_redirect!
    expect(response.body).to include("FTP reading updated. Refreshed 1 workout in Intervals.icu.")
    delete ftp_reading_path(reading)
    follow_redirect!
    expect(response.body).to include("FTP reading deleted. Refreshed 1 workout in Intervals.icu.")
    expect(profile.reload.ftp_watts).to eq(older.ftp_watts)
  end

  it "CYF-83 preserves the committed save and shows safe retry guidance after remote failure" do
    allow(client).to receive(:upsert_events).and_raise(IntervalsIcu::Client::AuthenticationError, "test-key must not leak")
    patch settings_path, params: { rider_profile: { ftp_watts: 300 } }
    expect(response).to have_http_status(:see_other)
    follow_redirect!
    expect(response.body).to include("Settings saved.", "FTP saved, but Intervals.icu workouts could not be refreshed.", "use Sync to retry.")
    expect(response.body).not_to include("Refreshed 1 workout", "test-key")
    expect(profile.reload.ftp_watts).to eq(300)
    expect(profile.ftp_readings.newest_first.first.ftp_watts).to eq(300)
  end

  it "CYF-83 keeps validation failures local and makes no refresh request" do
    patch ftp_reading_path(reading), params: { ftp_reading: { ftp_watts: 0 } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(profile.reload.ftp_watts).to eq(260)
    expect(client).not_to have_received(:upsert_events)
  end
end
