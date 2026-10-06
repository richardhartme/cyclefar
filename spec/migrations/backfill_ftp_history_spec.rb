require "rails_helper"
require Rails.root.join("db/migrate/20261006130000_backfill_ftp_history")

RSpec.describe BackfillFtpHistory do
  it "CYF-78 backfills only profiles without history using their original London date and current FTP" do
    profile = create(:rider_profile, ftp_watts: 310, created_at: Time.utc(2026, 9, 6, 23, 30))
    existing = create(:ftp_reading)
    completed = create(:planned_workout, :completed, training_plan: create(:training_plan, user: profile.user))
    snapshot = [ existing, completed, *completed.workout_steps, completed.workout_feedback ].map(&:attributes)
    connection = ActiveRecord::Base.connection
    connection.remove_index :ftp_readings, name: "index_ftp_readings_on_profile_and_recency"

    ActiveRecord::Migration.suppress_messages { described_class.new.up }

    expect(profile.ftp_readings.sole).to have_attributes(ftp_watts: 310, effective_on: Date.new(2026, 9, 7))
    expect([ existing, completed, *completed.workout_steps, completed.workout_feedback ].map { |row| row.reload.attributes }).to eq(snapshot)
    expect(existing.rider_profile.ftp_readings.count).to eq(1)
  end
end
