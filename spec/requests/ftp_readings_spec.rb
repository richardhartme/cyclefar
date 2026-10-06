require "rails_helper"

RSpec.describe "FTP history", type: :request do
  let(:user) { create(:user) }
  let(:profile) { create(:rider_profile, user: user, ftp_watts: 280) }
  let!(:older) { create(:ftp_reading, rider_profile: profile, ftp_watts: 250, effective_on: Date.current - 10) }
  let!(:newest) { create(:ftp_reading, rider_profile: profile, ftp_watts: 280, effective_on: Date.current - 2) }
  before { sign_in_as(user) }

  it "CYF-78 lists owned history newest first with edit and delete actions" do
    foreign = create(:ftp_reading, ftp_watts: 450)
    get settings_path
    html = Nokogiri::HTML(response.body)
    rows = html.css('table tbody tr')
    expect(rows.map(&:text).map(&:squish)).to match([ /280 W Current/, /250 W/ ])
    expect(rows.first.at_css("time")["datetime"]).to eq(newest.effective_on.iso8601)
    expect(html.at_css("a[href='#{edit_ftp_reading_path(older)}']")).to be_present
    expect(html.at_css("form[action='#{ftp_reading_path(older)}']")).to be_present
    expect(response.body).not_to include("450 W", edit_ftp_reading_path(foreign))
  end

  it "CYF-78 edits a historical reading through a labelled form" do
    get edit_ftp_reading_path(older)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reading date", "FTP (watts)", "Save reading")
    patch ftp_reading_path(older), params: { ftp_reading: { ftp_watts: 265, effective_on: Date.current - 7, rider_profile_id: create(:rider_profile).id } }
    expect(response).to redirect_to(settings_path)
    expect(response).to have_http_status(:see_other)
    expect(older.reload).to have_attributes(ftp_watts: 265, effective_on: Date.current - 7, rider_profile_id: profile.id)
    expect(profile.reload.ftp_watts).to eq(280)
    follow_redirect!
    expect(response.body).to include("FTP reading updated.", "265 W")
  end

  it "CYF-78 retains submitted fields and validation errors on invalid edits" do
    patch ftp_reading_path(newest), params: { ftp_reading: { ftp_watts: 0, effective_on: "bad" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(Nokogiri::HTML(response.body).text).to include("FTP reading could not be saved", "must be greater than 0", "can't be blank")
    expect(Nokogiri::HTML(response.body).at_css('input[name="ftp_reading[ftp_watts]"]')["value"]).to eq("0")
    expect(newest.reload.ftp_watts).to eq(280)
  end

  it "CYF-78 deletes the newest reading and prevents deleting the final reading" do
    delete ftp_reading_path(newest)
    expect(response).to redirect_to(settings_path)
    expect(profile.reload.ftp_watts).to eq(250)
    follow_redirect!
    expect(response.body).to include("FTP reading deleted.")
    expect(Nokogiri::HTML(response.body).at_css("form[action='#{ftp_reading_path(older)}']")).to be_nil
    delete ftp_reading_path(older)
    expect(response).to redirect_to(settings_path)
    follow_redirect!
    expect(response.body).to include("Keep at least one FTP reading")
    expect(older.reload).to be_persisted
  end

  it "USR-004 returns identical empty 404s for foreign and missing IDs on all history routes" do
    foreign = create(:ftp_reading)
    snapshot = foreign.attributes
    [ foreign.id, FtpReading.maximum(:id) + 100 ].each do |id|
      get edit_ftp_reading_path(id)
      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
      patch ftp_reading_path(id), params: { ftp_reading: { ftp_watts: 350 } }
      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
      delete ftp_reading_path(id)
      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
    end
    expect(foreign.reload.attributes).to eq(snapshot)
  end

  it "USR-001 requires authentication for history reads and mutations" do
    delete session_path
    get edit_ftp_reading_path(older)
    expect(response).to redirect_to(new_session_path)
    patch ftp_reading_path(older), params: { ftp_reading: { ftp_watts: 350 } }
    expect(response).to redirect_to(new_session_path)
    delete ftp_reading_path(older)
    expect(response).to redirect_to(new_session_path)
    expect(older.reload.ftp_watts).to eq(250)
  end
end
