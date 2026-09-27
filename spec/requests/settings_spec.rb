require "rails_helper"

RSpec.describe "Settings", type: :request do
  let(:user) { create(:user) }
  before { sign_in_as(user) }

  it "SET-001 allows first-run settings without creating records on GET" do
    get settings_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Current FTP (watts)", "Intervals.icu API key")
    expect(RiderProfile.count).to eq(0)
  end

  it "SET-001 saves FTP and history through the Settings form" do
    patch settings_path, params: { rider_profile: { ftp_watts: 260 } }
    expect(response).to redirect_to(settings_path)
    expect(response).to have_http_status(:see_other)
    follow_redirect!
    expect(response.body).to include("Settings saved.")
    expect(user.rider_profile.ftp_watts).to eq(260)
    expect(FtpReading.sole.ftp_watts).to eq(260)
  end

  it "SET-001 renders useful errors without persisting invalid settings" do
    patch settings_path, params: { rider_profile: { ftp_watts: "bad" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Settings could not be saved", "is not a number")
    expect(RiderProfile.count).to eq(0)
    expect(FtpReading.count).to eq(0)
  end

  it "SET-002 never renders a submitted key, including on validation failure" do
    patch settings_path, params: { rider_profile: { ftp_watts: 260, intervals_icu_api_key: "sensitive-test-key" } }
    follow_redirect!
    expect(response.body).to include("Saved API key: ••••••••")
    expect(response.body).not_to include("sensitive-test-key")
    expect(Nokogiri::HTML(response.body).at_css('input[type="password"]')["value"]).to be_nil
    patch settings_path, params: { rider_profile: { ftp_watts: 0, intervals_icu_api_key: "replacement-secret" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).not_to include("replacement-secret", "sensitive-test-key")
    expect(user.rider_profile.reload.intervals_icu_api_key).to eq("sensitive-test-key")
  end

  it "SET-002 filters API keys from request and SQL logs" do
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    original_rails_logger = Rails.logger
    original_ar_logger = ActiveRecord::Base.logger
    Rails.logger = logger
    ActiveRecord::Base.logger = logger
    patch settings_path, params: { rider_profile: { ftp_watts: 260, intervals_icu_api_key: "never-log-this-key" } }
    expect(response).to have_http_status(:see_other)
    expect(output.string).not_to include("never-log-this-key")
    expect(output.string).to include("[FILTERED]")
    expect(
      ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(
        "rider_profile" => { "intervals_icu_api_key" => "never-log-this-key" }
          )).to eq("rider_profile" => { "intervals_icu_api_key" => "[FILTERED]" })
  ensure
    Rails.logger = original_rails_logger
    ActiveRecord::Base.logger = original_ar_logger
  end

  it "SET-002 removes a saved key without changing FTP history" do
    patch settings_path, params: { rider_profile: { ftp_watts: 260, intervals_icu_api_key: "saved-key" } }
    patch settings_path, params: { rider_profile: { ftp_watts: 260, clear_intervals_icu_api_key: "1" } }
    expect(user.rider_profile.reload.intervals_icu_api_key).to be_nil
    expect(FtpReading.count).to eq(1)
  end
end
