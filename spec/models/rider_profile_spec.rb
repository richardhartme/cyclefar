require "rails_helper"

RSpec.describe RiderProfile, type: :model do
  it "USR-002 permits one profile per user and no singleton ID" do
    first = create(:user, email_address: "first@example.com")
    second = create(:user, email_address: "second@example.com")
    profile = create(:rider_profile, user: first, id: 42)
    expect(profile.id).to eq(42)
    expect(build(:rider_profile, user: first)).not_to be_valid
    expect_database_rejection(ActiveRecord::RecordNotUnique) do
      build(:rider_profile, user: first).save!(validate: false)
    end
    expect(create(:rider_profile, user: second)).to be_persisted
  end

  it "USR-002 requires an existing user in PostgreSQL" do
    expect(build(:rider_profile, user: nil)).not_to be_valid
    expect_database_rejection(ActiveRecord::NotNullViolation) do
      described_class.insert_all!([ { ftp_watts: 260, created_at: Time.current, updated_at: Time.current } ])
    end
    expect_database_rejection(ActiveRecord::InvalidForeignKey) do
      described_class.insert_all!([ { user_id: 999_999, ftp_watts: 260, created_at: Time.current, updated_at: Time.current } ])
    end
  end

  [ nil, 0, -1, 260.5, "abc", "260x" ].each do |value|
    it "SET-001 rejects FTP #{value.inspect}" do
      expect(build(:rider_profile, ftp_watts: value)).not_to be_valid
    end
  end

  it "SET-001 enforces positive FTP in PostgreSQL" do
    profile = create(:rider_profile)
    expect_database_rejection { profile.update_columns(ftp_watts: 0) }
  end

  it "SET-002 encrypts the key at rest and filters model inspection" do
    profile = create(:rider_profile, intervals_icu_api_key: "secret-test-key")
    ciphertext = described_class.connection.select_value("SELECT intervals_icu_api_key FROM rider_profiles WHERE id = #{profile.id}")
    expect(ciphertext).not_to include("secret-test-key")
    expect(JSON.parse(ciphertext)).to include("p", "h")
    expect(profile.reload.intervals_icu_api_key).to eq("secret-test-key")
    expect(profile.inspect).not_to include("secret-test-key")
  end
end
