require "rails_helper"

RSpec.describe LegacyOwnership::Backfill do
  let(:connection) { ActiveRecord::Base.connection }

  def backfill(owner_id: nil)
    described_class.new(connection: connection, owner_id: owner_id)
  end

  it "permits an empty database without selecting an owner" do
    create(:user, email_address: "first@example.com")
    create(:user, email_address: "second@example.com")
    expect(backfill.preflight!).to include(owner: nil)
    expect { backfill.backfill! }.not_to raise_error
  end

  it "requires an owner even when detached sync metadata is the only legacy record" do
    create(:intervals_icu_sync, planned_workout: nil, external_id: "cyclefar-workout-deleted-1")
    expect { backfill.preflight! }.to raise_error(described_class::UnsafeData, /existing CYCLEFAR_LEGACY_OWNER_USER_ID/)
  end

  it "requires an explicitly selected existing owner when legacy records exist" do
    profile = create(:rider_profile)
    expect(backfill.report[:counts]).to include(rider_profiles: 1)
    expect { backfill.preflight! }.to raise_error(described_class::UnsafeData, /existing CYCLEFAR_LEGACY_OWNER_USER_ID/)
    expect { backfill(owner_id: 99_999).preflight! }.to raise_error(described_class::UnsafeData, /does not exist/)
    expect(profile.reload.user_id).to be_present
  end

  it "backfills one selected account while preserving completed history, FTP readings and linked/detached external IDs" do
    owner = create(:user, email_address: "owner@example.com")
    create(:user, email_address: "other@example.com")
    profile = create(:rider_profile, user: owner, intervals_icu_api_key: "private-key")
    reading = create(:ftp_reading, rider_profile: profile)
    plan = create(:training_plan, user: owner)
    completed = create(:planned_workout, :completed, training_plan: plan)
    linked = create(:intervals_icu_sync, planned_workout: completed, external_id: "cyclefar-workout-#{completed.id}")
    detached = create(:intervals_icu_sync, planned_workout: nil, external_id: "cyclefar-workout-deleted-42")
    original = {
      encrypted_key: connection.select_value("SELECT intervals_icu_api_key FROM rider_profiles WHERE id = #{profile.id}"),
      snapshot: completed.completed_target_snapshot.deep_dup,
      ftp: completed.completed_ftp_watts,
      steps: completed.workout_steps.pluck(:id, :target_low_pct_ftp, :target_high_pct_ftp),
      reading: reading.attributes,
      external_ids: [ linked.external_id, detached.external_id ]
    }

    inventory = backfill(owner_id: owner.id).preflight!
    expect(inventory[:owner]).to eq("id" => owner.id, "email_address" => owner.email_address)
    expect(inventory[:counts]).to include(completed_workouts: 1, sync_linked: 1, sync_detached: 1)
    expect(inventory.to_s).not_to include("private-key")
    2.times { backfill(owner_id: owner.id).backfill! }

    expect([ profile.reload.user_id, plan.reload.user_id, linked.reload.user_id, detached.reload.user_id ]).to eq([ owner.id ] * 4)
    expect(connection.select_value("SELECT intervals_icu_api_key FROM rider_profiles WHERE id = #{profile.id}")).to eq(original[:encrypted_key])
    expect(completed.reload.completed_target_snapshot).to eq(original[:snapshot])
    expect(completed.completed_ftp_watts).to eq(original[:ftp])
    expect(completed.workout_steps.pluck(:id, :target_low_pct_ftp, :target_high_pct_ftp)).to eq(original[:steps])
    expect(reading.reload.attributes).to eq(original[:reading])
    expect([ linked.external_id, detached.external_id ]).to eq(original[:external_ids])
  end

  it "stops before changing any row when a previous owner conflicts" do
    selected = create(:user, email_address: "selected@example.com")
    other = create(:user, email_address: "other@example.com")
    profile = create(:rider_profile, user: selected)
    plan = create(:training_plan, user: other)

    expect { backfill(owner_id: selected.id).backfill! }.to raise_error(described_class::UnsafeData, /different owner/)
    expect(profile.reload.user_id).to eq(selected.id)
    expect(plan.reload.user_id).to eq(other.id)
  end

  it "rejects an invalid owner value" do
    create(:rider_profile)
    expect { backfill(owner_id: "first").preflight! }.to raise_error(described_class::UnsafeData, /positive integer/)
  end
end
