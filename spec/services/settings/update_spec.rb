require "rails_helper"

RSpec.describe Settings::Update do
  uses_transaction "USR-002 serializes concurrent first Settings saves for two owners"

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

  it "CYF-78 retains backdated readings without replacing the newest FTP" do
    update_settings({ ftp_watts: 275 }, effective_on: Date.new(2026, 9, 8))
    update_settings({ ftp_watts: 260 }, effective_on: Date.new(2026, 9, 7))
    expect(profile.reload.ftp_watts).to eq(275)
    expect(profile.ftp_readings.newest_first.pluck(:ftp_watts)).to eq([ 275, 260 ])
  end

  it "CYF-78 uses the last saved entry for same-day FTP changes" do
    update_settings({ ftp_watts: 260 })
    update_settings({ ftp_watts: 275 })
    expect(profile.reload.ftp_watts).to eq(275)
    expect(profile.ftp_readings.newest_first.pluck(:ftp_watts)).to eq([ 275, 260 ])
  end

  it "USR-002 serializes concurrent first Settings saves for two owners" do
    owners = []
    [ 260, 310 ].each do |ftp|
      owners << [ User.create!(email_address: "settings-#{SecureRandom.hex(8)}@example.com", password: "password").id, ftp ]
    end
    ready = Queue.new
    start = Queue.new
    threads = owners.flat_map do |owner_id, ftp|
      2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            owner = User.find(owner_id)
            profile = owner.rider_profile || owner.build_rider_profile
            [ owner_id, described_class.new(profile: profile, attributes: { ftp_watts: ftp }).call.id ]
          end
        end
      end
    end

    4.times { ready.pop }
    4.times { start << true }
    results = threads.map(&:value)

    owners.each do |owner_id, ftp|
      profile = RiderProfile.find_by!(user_id: owner_id)
      expect(results.select { |id, _| id == owner_id }.map(&:last).uniq).to eq([ profile.id ])
      expect(profile.ftp_watts).to eq(ftp)
      expect(profile.ftp_readings.pluck(:ftp_watts)).to eq([ ftp ])
    end
    expect(RiderProfile.where(user_id: owners.map(&:first)).count).to eq(2)
  ensure
    threads&.size&.times { start << true }
    threads&.each(&:join)
    if owners&.any?
      owner_ids = owners.map(&:first)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          FtpReading.where(rider_profile_id: RiderProfile.where(user_id: owner_ids).select(:id)).delete_all
          RiderProfile.where(user_id: owner_ids).delete_all
          User.where(id: owner_ids).delete_all
        end
      end.value
    end
  end
end
