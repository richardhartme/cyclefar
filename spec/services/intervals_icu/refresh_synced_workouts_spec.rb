require "rails_helper"

RSpec.describe IntervalsIcu::RefreshSyncedWorkouts do
  # Freeze time before the let! records below so their Date.current offsets are relative to the frozen date.
  before { travel_to Time.zone.local(2026, 10, 12, 12) }

  let(:user) { create(:user) }
  let!(:profile) { create(:rider_profile, user: user, ftp_watts: 260, intervals_icu_api_key: "own-key") }
  let!(:reading) { create(:ftp_reading, rider_profile: profile, ftp_watts: 260, effective_on: Date.current - 2) }
  let(:plan) { create(:training_plan, :event, user: user, starts_on: Date.current - 7, ends_on: Date.current + 50) }
  let(:client) { instance_double(IntervalsIcu::Client) }

  before do
    allow(IntervalsIcu::Client).to receive(:new).with(api_key: "own-key").and_return(client)
    allow(client).to receive(:upsert_events) do |payloads|
      payloads.reverse.map.with_index { |payload, i| { "external_id" => payload.fetch(:external_id), "id" => i + 100 } }
    end
  end
  after { travel_back }

  def workout(days, **attributes)
    create(:planned_workout, :structured, training_plan: plan, scheduled_on: Date.current + days, **attributes)
  end

  def confirm(workout)
    create(
      :intervals_icu_sync,
      planned_workout: workout,
      intervals_event_id: workout.id,
      last_synced_at: 1.day.ago,
      payload_digest: "previous-payload")
  end

  def save_ftp(watts = 300)
    update = Settings::Update.new(profile: profile, attributes: { ftp_watts: watts })
    update.call
    update.refresh_result
  end

  it "CYF-83 refreshes all confirmed upcoming exports including today, openers and distant structures" do
    selected = [ workout(0), workout(2, kind: :opener, duration_minutes: 30), workout(4), workout(20) ]
    syncs = selected.map { |w| confirm(w) }
    steps = selected.map { |w| w.workout_steps.map(&:attributes) }
    dates = selected.map(&:scheduled_on)
    payloads = nil
    allow(client).to receive(:upsert_events) do |events|
      payloads = events
      events.reverse.map.with_index { |event, i| { "external_id" => event[:external_id], "id" => 100 + i } }
    end

    expect(save_ftp).to have_attributes(refreshed_count: 4, error: nil)

    expect(payloads.pluck(:external_id)).to eq(syncs.map(&:external_id))
    expect(payloads.pluck(:icu_ftp)).to eq([ 300 ] * 4)
    expect(payloads.first).to include(description: "- Steady endurance 1h 60-70%", joules: 702000)
    expect(selected.map { |w| w.reload.workout_steps.map(&:attributes) }).to eq(steps)
    expect(selected.map(&:scheduled_on)).to eq(dates)
    expect(Workouts::StepDefinition.from(selected.first.workout_steps.first).target_watts(ftp_watts: 300)).to include(low_watts: 180, high_watts: 210)
    expect(syncs.map { |s| s.reload.intervals_event_id }).to eq([ 103, 102, 101, 100 ])
    expect(syncs.map(&:last_synced_at)).to all(eq(Time.current))
    expect(syncs.map(&:payload_digest)).not_to include("previous-payload")
    expect(client).not_to receive(:delete_events)
  end

  it "CYF-83 excludes every ineligible/never-confirmed export without deleting identities or changing history" do
    selected = workout(0)
    confirm(selected)
    excluded = [ workout(-1), workout(2, status: :missed), workout(3) ]
    excluded.last.workout_steps.destroy_all
    excluded.last.update!(detail_status: :outline)
    completed = create(:planned_workout, :completed, training_plan: plan, scheduled_on: Date.current + 4)
    excluded << completed
    create(:target_event, training_plan: plan, event_on: plan.ends_on)
    excluded << workout(50)
    create(:time_off_period, training_plan: plan, starts_on: Date.current + 7, ends_on: Date.current + 9)
    excluded.concat([ 7, 8, 9 ].map { |day| workout(day) })
    archived = create(:training_plan, :archived, user: user)
    excluded << create(:planned_workout, :structured, training_plan: archived)
    excluded_syncs = excluded.map { |w| confirm(w) }
    unsynced = workout(11)
    uncertain = create(:intervals_icu_sync, planned_workout: workout(12))
    detached = create(:intervals_icu_sync, user: user, planned_workout: nil, external_id: "cyclefar-detached")
    other_profile = create(:rider_profile, intervals_icu_api_key: "foreign-key")
    foreign = create(:planned_workout, :structured, training_plan: create(:training_plan, user: other_profile.user), scheduled_on: Date.current)
    other_sync = confirm(foreign)
    stable = [ *excluded_syncs, uncertain, detached, other_sync, completed, *completed.workout_steps, completed.workout_feedback, other_profile ].map(&:attributes)

    expect(save_ftp).to have_attributes(refreshed_count: 1, error: nil)

    expect(client).to have_received(:upsert_events).with([ hash_including(external_id: selected.intervals_icu_sync.external_id, icu_ftp: 300) ])
    expect([ *excluded_syncs, uncertain, detached, other_sync, completed, *completed.workout_steps, completed.workout_feedback, other_profile ].map { |r| r.reload.attributes }).to eq(stable)
    expect(unsynced.reload.intervals_icu_sync).to be_nil
  end

  it "CYF-83 performs no HTTP for unchanged current FTP, old-history edits, credential-only saves or invalid FTP" do
    confirm(workout(0))
    expect(save_ftp(260)).to be_nil
    Settings::Update.new(profile: profile, attributes: { intervals_icu_api_key: "own-key" }).call
    older = create(:ftp_reading, rider_profile: profile, ftp_watts: 250, effective_on: Date.current - 20)
    history = Settings::FtpHistory.new(profile: profile)
    history.update!(reading_id: older.id, attributes: { ftp_watts: 270 })
    expect(history.refresh_result).to be_nil
    history.destroy!(reading_id: older.id)
    expect(history.refresh_result).to be_nil
    expect { save_ftp(0) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(profile.reload.ftp_watts).to eq(260)
    expect(client).not_to have_received(:upsert_events)
  end

  it "CYF-83 refreshes after history edits, date reordering and newest-reading deletion fallback" do
    confirm(workout(0))
    older = create(:ftp_reading, rider_profile: profile, ftp_watts: 250, effective_on: Date.current - 20)
    history = Settings::FtpHistory.new(profile: profile)
    history.update!(reading_id: reading.id, attributes: { ftp_watts: 280 })
    expect(history.refresh_result).to have_attributes(refreshed_count: 1, error: nil)
    history.update!(reading_id: older.id, attributes: { effective_on: Date.current })
    expect(history.refresh_result).to have_attributes(refreshed_count: 1, error: nil)
    history.destroy!(reading_id: older.id)
    expect(history.refresh_result).to have_attributes(refreshed_count: 1, error: nil)
    expect(client).to have_received(:upsert_events).with([ hash_including(icu_ftp: 280) ]).twice
    expect(client).to have_received(:upsert_events).with([ hash_including(icu_ftp: 250) ]).once
  end

  it "CYF-83 saves FTP without HTTP when no confirmed eligible exports or active plan exist" do
    expect(save_ftp).to have_attributes(refreshed_count: 0, error: nil)
    create(:intervals_icu_sync, planned_workout: workout(0))
    expect(save_ftp(310)).to have_attributes(refreshed_count: 0, error: nil)
    profile.update!(intervals_icu_api_key: nil)
    expect(save_ftp(320)).to have_attributes(refreshed_count: 0, error: nil)
    expect(client).not_to have_received(:upsert_events)
  end

  it "CYF-83 keeps the save and confirmed metadata when the key is missing" do
    sync = confirm(workout(0))
    before = sync.attributes
    profile.update!(intervals_icu_api_key: nil)
    expect(save_ftp).to have_attributes(refreshed_count: 0, error: described_class::FAILURE_MESSAGE)
    expect(profile.reload.ftp_watts).to eq(300)
    expect(sync.reload.attributes).to eq(before)
    expect(client).not_to have_received(:upsert_events)
  end

  [ IntervalsIcu::Client::AuthenticationError, IntervalsIcu::Client::RequestError ].each do |error|
    it "CYF-83 retains local FTP and metadata after #{error}, then allows manual recovery" do
      w = workout(0)
      sync = confirm(w)
      before = sync.attributes
      allow(client).to receive(:upsert_events).and_raise(error, "secret must not leak")
      expect(save_ftp).to have_attributes(refreshed_count: 0, error: described_class::FAILURE_MESSAGE)
      expect(profile.reload.ftp_watts).to eq(300)
      expect(w.reload.estimated_work_kj).to eq(702)
      expect(sync.reload.attributes).to eq(before)
      allow(client).to receive(:upsert_events) { |events| events.map { |event| { "id" => 101, "external_id" => event[:external_id] } } }
      allow(client).to receive(:delete_events)
      IntervalsIcu::SyncCalendar.new(plan: plan, profile: profile, client: client).call
      expect(sync.reload).to have_attributes(external_id: before["external_id"], intervals_event_id: 101, last_synced_at: Time.current)
      expect(IntervalsIcuSync.where(planned_workout: w).count).to eq(1)
    end
  end

  [ nil, [], {}, :duplicate, :nonpositive ].each do |response|
    it "CYF-83 does not advance metadata for invalid/incomplete confirmations #{response}" do
      syncs = [ confirm(workout(0)), confirm(workout(1)) ]
      before = syncs.map(&:attributes)
      allow(client).to receive(:upsert_events) do |events|
        case response
        when :duplicate then [ { "id" => 10, "external_id" => events.first[:external_id] } ] * 2
        when :nonpositive then events.map { |event| { "id" => 0, "external_id" => event[:external_id] } }
        else response
        end
      end
      expect(save_ftp.error).to eq(described_class::FAILURE_MESSAGE)
      expect(syncs.map { |s| s.reload.attributes }).to eq(before)
      expect(profile.reload.ftp_watts).to eq(300)
    end
  end

  it "CYF-83 never reattaches an identity detached by workout removal during upload" do
    w = workout(0)
    sync = confirm(w)
    previous_metadata = sync.slice(:payload_digest, :last_synced_at, :intervals_event_id)
    allow(client).to receive(:upsert_events) do |events|
      Workouts::Remover.new(w).call
      events.map { |event| { "id" => 101, "external_id" => event[:external_id] } }
    end
    expect(save_ftp.error).to eq(described_class::FAILURE_MESSAGE)
    expect(sync.reload.planned_workout_id).to be_nil
    expect(sync.slice(*previous_metadata.keys)).to eq(previous_metadata)
  end
end
