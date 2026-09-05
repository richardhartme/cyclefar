require "rails_helper"

RSpec.describe RiderProfile, type: :model do
  it "SET-001 starts with an unsaved singleton and no invented FTP" do
    expect(described_class.current).to have_attributes(id: 1, ftp_watts: nil)
    expect(described_class.count).to eq(0)
  end

  [ nil, 0, -1, 260.5, "abc", "260x" ].each do |value|
    it "SET-001 rejects FTP #{value.inspect}" do
      expect(build(:rider_profile, ftp_watts: value)).not_to be_valid
    end
  end

  it "SET-001 returns the saved singleton and rejects a second profile" do
    profile = create(:rider_profile)
    expect(described_class.current).to eq(profile)
    expect(build(:rider_profile)).not_to be_valid
    expect_database_rejection { described_class.insert_all!([ { id: 2, ftp_watts: 250 } ]) }
  end

  it "SET-001 enforces positive FTP in PostgreSQL" do
    profile = create(:rider_profile)
    expect_database_rejection { profile.update_columns(ftp_watts: 0) }
  end

  it "SET-002 encrypts the key at rest and filters model inspection" do
    profile = create(:rider_profile, intervals_icu_api_key: "secret-test-key")
    ciphertext = described_class.connection.select_value("SELECT intervals_icu_api_key FROM rider_profiles WHERE id = 1")
    expect(ciphertext).not_to include("secret-test-key")
    expect(JSON.parse(ciphertext)).to include("p", "h")
    expect(profile.reload.intervals_icu_api_key).to eq("secret-test-key")
    expect(profile.inspect).not_to include("secret-test-key")
  end
end
