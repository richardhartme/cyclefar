require "rails_helper"

RSpec.describe Settings::Update do
  let(:user) { create(:user) }

  def profile
    user.rider_profile || user.build_rider_profile
  end

  def update_settings(attributes, effective_on: Date.new(2026, 9, 7))
    described_class.new(profile: profile, attributes: attributes, effective_on: effective_on).call
  end

  it "SET-001 records initial FTP and subsequent changes with effective dates" do
    update_settings({ ftp_watts: 260 })
    update_settings({ ftp_watts: 275 }, effective_on: Date.new(2026, 9, 8))
    expect(FtpReading.order(:id).pluck(:ftp_watts, :effective_on)).to eq(
      [
            [ 260, Date.new(2026, 9, 7) ], [ 275, Date.new(2026, 9, 8) ]
          ])
    expect(profile.reload.ftp_watts).to eq(275)
  end

  it "SET-001 uses the application calendar date by default" do
    travel_to Time.zone.local(2026, 9, 8, 0, 30) do
      described_class.new(profile: profile, attributes: { ftp_watts: 260 }).call
      expect(FtpReading.sole.effective_on).to eq(Date.new(2026, 9, 8))
    end
  end

  it "SET-001 does not create history when only the key changes or FTP is unchanged" do
    update_settings({ ftp_watts: 260 })
    expect { update_settings({ ftp_watts: "260", intervals_icu_api_key: "test-key" }) }.not_to change(FtpReading, :count)
  end

  it "SET-001 rolls back settings if history cannot be saved" do
    update_settings({ ftp_watts: 260 })
    expect { update_settings({ ftp_watts: 275 }, effective_on: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(profile.reload.ftp_watts).to eq(260)
    expect(FtpReading.count).to eq(1)
  end

  it "SET-001 preserves settings and history on invalid FTP" do
    update_settings({ ftp_watts: 260, intervals_icu_api_key: "original-key" })
    expect { update_settings({ ftp_watts: 0, intervals_icu_api_key: "new-key" }) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(profile.reload).to have_attributes(ftp_watts: 260, intervals_icu_api_key: "original-key")
    expect(FtpReading.count).to eq(1)
  end

  it "SET-001 reuses the user's profile when callers hold stale first-run objects" do
    stale = profile
    update_settings({ ftp_watts: 260 })
    described_class.new(profile: stale, attributes: { ftp_watts: 275 }).call
    expect(RiderProfile.count).to eq(1)
    expect(FtpReading.order(:id).pluck(:ftp_watts)).to eq([ 260, 275 ])
  end

  it "SET-002 preserves, replaces, and explicitly removes the saved secret" do
    update_settings({ ftp_watts: 260, intervals_icu_api_key: "first-key" })
    update_settings({ ftp_watts: 260, intervals_icu_api_key: "" })
    expect(profile.reload.intervals_icu_api_key).to eq("first-key")
    update_settings({ ftp_watts: 260, intervals_icu_api_key: "second-key" })
    expect(profile.reload.intervals_icu_api_key).to eq("second-key")
    update_settings({ ftp_watts: 260, clear_intervals_icu_api_key: "1" })
    expect(profile.reload.intervals_icu_api_key).to be_nil
  end

  it "SET-001 keeps recorded FTP readings immutable through model operations" do
    update_settings({ ftp_watts: 260 })
    reading = FtpReading.sole
    expect { reading.update!(ftp_watts: 300) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { reading.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
