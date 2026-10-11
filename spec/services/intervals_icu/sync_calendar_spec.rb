require "rails_helper"

RSpec.describe IntervalsIcu::SyncCalendar do
  class FakeClient
    attr_reader :upserts, :deletions

    def initialize
      @upserts = []
      @deletions = []
    end

    def upsert_events(events)
      @upserts << events
      events.map.with_index { |event, index| { "external_id" => event.fetch(:external_id), "id" => index + 100 } }
    end

    def delete_events(external_ids)
      @deletions << external_ids
      []
    end
  end

  class SyncRecordingConnection
    Response = Struct.new(:code, :body)
    attr_reader :requests

    def initialize
      @requests = []
    end

    def request(request)
      @requests << request
      payload = JSON.parse(request.body)
      body = if request.path.include?("bulk-delete")
        { "eventsDeleted" => payload.size }
      else
        payload.map.with_index { |event, index| { "external_id" => event.fetch("external_id"), "id" => index + 100 } }
      end
      Response.new("200", JSON.generate(body))
    end
  end

  let(:plan) { create(:training_plan, :event, starts_on: Date.current - 7, ends_on: Date.current + 30) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }
  let(:profile) { create(:rider_profile, user: plan.user, ftp_watts: 300, intervals_icu_api_key: "test-api-key") }
  let(:client) { FakeClient.new }

  before { travel_to Time.zone.local(2026, 10, 12, 12) }
  after { travel_back }

  it "includes today and distant structures without generating outlines or changing history" do
    distant = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 20)
    today = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current)
    opener = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, kind: :opener, scheduled_on: Date.current + 2)
    outline = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 21)
    past = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 1)
    missed = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, status: :missed, scheduled_on: Date.current + 3)
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 4)
    archive = create(:training_plan, :archived, user: plan.user, starts_on: plan.starts_on, ends_on: plan.ends_on)
    archived = create(:planned_workout, :structured, training_plan: archive, scheduled_on: Date.current + 5)
    create(:target_event, training_plan: plan, event_on: plan.ends_on)
    event_date_workout = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: plan.ends_on)
    create(:time_off_period, training_plan: plan, starts_on: Date.current + 7, ends_on: Date.current + 9)
    blocked = [ 7, 8, 9 ].map { |days| create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + days) }
    all = [ distant, today, opener, outline, past, missed, completed, archived, event_date_workout, *blocked ]
    before = all.map { |workout| [ workout.attributes, workout.workout_steps.map(&:attributes), workout.workout_feedback&.attributes ] }

    result = described_class.new(plan: plan, profile: profile, client: client).call

    expect(result).to have_attributes(synced_count: 3, removed_count: 0)
    expect(client.upserts.sole.pluck(:external_id)).to eq([ today, opener, distant ].map { |workout| "cyclefar-workout-#{workout.id}" })
    expect(all.map { |workout| [ workout.reload.attributes, workout.workout_steps.reload.map(&:attributes), workout.workout_feedback&.reload&.attributes ] }).to eq(before)
  end

  it "cleans tracked events that become outlines or fall within time off" do
    workouts = create_upcoming_workouts(4)
    described_class.new(plan: plan, profile: profile, client: client).call
    workouts.first.workout_steps.destroy_all
    workouts.first.update!(detail_status: :outline)
    create(:time_off_period, training_plan: plan, starts_on: workouts.last.scheduled_on, ends_on: workouts.last.scheduled_on)

    result = described_class.new(plan: plan, profile: profile, client: client).call

    expect(result).to have_attributes(synced_count: 2, removed_count: 2)
    expect(client.deletions.last).to match_array([ workouts.first, workouts.last ].map { |workout| "cyclefar-workout-#{workout.id}" })
    expect(workouts.first.reload).to be_outline
    expect(workouts.first.workout_steps).to be_empty
  end

  it "maps out-of-order bulk confirmations by external ID" do
    workouts = create_upcoming_workouts(4)
    allow(client).to receive(:upsert_events).and_wrap_original { |original, events| original.call(events).reverse }

    described_class.new(plan: plan, profile: profile, client: client).call

    expect(workouts.map { |workout| workout.reload.intervals_icu_sync.intervals_event_id }).to eq([ 100, 101, 102, 103 ])
  end

  it "exports edits and current FTP for every workout while retaining identities" do
    allow(IntervalsIcu::Client).to receive(:new).and_return(client)
    workouts = create_upcoming_workouts(4)
    described_class.new(plan: plan, profile: profile, client: client).call
    identities = IntervalsIcuSync.where(planned_workout: workouts).order(:planned_workout_id).pluck(:id, :external_id)
    original_description = client.upserts.first.last.fetch(:description)
    Workouts::ManualEditor.new(workouts.last).apply!(action: :change, subtype: :threshold, duration_minutes: 75)
    Settings::Update.new(profile: profile, attributes: { ftp_watts: 320 }).call

    described_class.new(plan: plan, profile: profile.reload, client: client).call

    expect(client.upserts.last.pluck(:icu_ftp)).to eq([ 320, 320, 320, 320 ])
    expect(client.upserts.last.last).to include(name: workouts.last.reload.name, moving_time: 4500)
    expect(client.upserts.last.last.fetch(:description)).not_to eq(original_description)
    expect(client.upserts.last.last.fetch(:description)).to include("%")
    expect(IntervalsIcuSync.where(planned_workout: workouts).order(:planned_workout_id).pluck(:id, :external_id)).to eq(identities)
    expect(client.deletions.flatten).to be_empty
  end

  [ nil, {}, [ { "external_id" => "unrelated", "id" => 1 } ] ].each do |response|
    it "retains retry identities and skips cleanup for an invalid bulk response #{response.inspect}" do
      workouts = create_upcoming_workouts(3)
      stale = create(:intervals_icu_sync, user: plan.user, planned_workout: nil, external_id: "cyclefar-deleted")
      allow(client).to receive(:upsert_events).and_return(response)

      expect { described_class.new(plan: plan, profile: profile, client: client).call }.to raise_error(IntervalsIcu::Client::RequestError, /did not confirm every workout/)

      expect(client.deletions).to be_empty
      expect(stale.reload).to be_persisted
      expect(IntervalsIcuSync.where(planned_workout: workouts).pluck(:last_synced_at)).to eq([ nil, nil, nil ])
      expect(described_class.new(plan: plan, profile: profile, client: FakeClient.new).call).to have_attributes(synced_count: 3, removed_count: 1)
    end
  end

  it "does not mark a partial bulk confirmation successful or delete stale events" do
    workouts = create_upcoming_workouts(4)
    stale = create(:intervals_icu_sync, user: plan.user, planned_workout: nil, external_id: "cyclefar-deleted")
    allow(client).to receive(:upsert_events).and_wrap_original { |original, events| original.call(events).first(3) }

    expect { described_class.new(plan: plan, profile: profile, client: client).call }.to raise_error(IntervalsIcu::Client::RequestError, /Sync again/)

    expect(client.deletions).to be_empty
    expect(stale.reload).to be_persisted
    expect(IntervalsIcuSync.where(planned_workout: workouts).pluck(:last_synced_at)).to eq([ nil, nil, nil, nil ])
  end

  it "ICU-001 syncs all upcoming structured workouts in date order with the current FTP" do
    workouts = create_upcoming_workouts(3)

    result = described_class.new(plan: plan, profile: profile, client: client).call

    expect(result).to have_attributes(synced_count: 3, removed_count: 0)
    expect(client.upserts.sole.map { |event| event.fetch(:external_id) }).to eq(workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
    expect(client.upserts.sole.map { |event| event.fetch(:icu_ftp) }).to eq([ 300, 300, 300 ])
    expect(IntervalsIcuSync.pluck(:external_id)).to match_array(workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
  end

  it "upserts repeat syncs without creating duplicate local metadata" do
    create_upcoming_workouts(4)

    2.times { described_class.new(plan: plan, profile: profile, client: client).call }

    expect(IntervalsIcuSync.count).to eq(4)
    expect(client.upserts.map { |events| events.map { |event| event.fetch(:external_id) } }.uniq.size).to eq(1)
  end

  it "keeps a synced workout moved later than the first pair and beyond the detail horizon" do
    workouts = create_upcoming_workouts(3)
    described_class.new(plan: plan, profile: profile, client: client).call
    moved_external_id = "cyclefar-workout-#{workouts.first.id}"
    workouts.first.update!(scheduled_on: Date.current + 20)

    result = described_class.new(plan: plan, profile: profile, client: client).call

    expect(result).to have_attributes(synced_count: 3, removed_count: 0)
    expect(client.deletions.last).to be_empty
    expect(IntervalsIcuSync.where(external_id: moved_external_id)).to exist
    expect(client.upserts.last.last).to include(external_id: moved_external_id, start_date_local: "#{Date.current + 20}T00:00:00")
  end

  it "removes an owned event when its planned workout is deleted" do
    workouts = create_upcoming_workouts(3)
    described_class.new(plan: plan, profile: profile, client: client).call
    deleted_external_id = "cyclefar-workout-#{workouts.first.id}"
    Workouts::Remover.new(workouts.first).call

    result = described_class.new(plan: plan, profile: profile, client: client).call

    expect(result.removed_count).to eq(1)
    expect(client.deletions.last).to eq([ deleted_external_id ])
    expect(IntervalsIcuSync.where(external_id: deleted_external_id)).not_to exist
  end

  it "never supplies unrelated external IDs to the API" do
    create_upcoming_workouts(2)
    described_class.new(plan: plan, profile: profile, client: client).call

    expect(client.upserts.flatten.map { |event| event.fetch(:external_id) }).to all(start_with("cyclefar-"))
    expect(client.deletions.flatten).not_to include("unrelated-calendar-event")
  end

  it "does not call the API when the Intervals.icu key is missing" do
    profile.update!(intervals_icu_api_key: nil)

    expect { described_class.new(plan: plan, profile: profile, client: client).call }.to raise_error(IntervalsIcu::Client::RequestError, /Add an Intervals.icu API key/)
    expect(client.upserts).to be_empty
  end

  it "rejects a stale plan instance after archival without recreating remote events" do
    create_upcoming_workouts(1)
    TrainingPlan.find(plan.id).update!(status: :archived)

    expect { described_class.new(plan: plan, profile: profile, client: client).call }.to raise_error(IntervalsIcu::Client::RequestError, /active plan/)
    expect(client.upserts).to be_empty
    expect(client.deletions).to be_empty
  end

  it "reconciles only the current rider's linked and detached sync records" do
    workouts = create_upcoming_workouts(4)
    other_plan = create(:training_plan, starts_on: Date.current, ends_on: Date.current + 30)
    other_phase = create(:plan_phase, training_plan: other_plan, starts_on: other_plan.starts_on, ends_on: other_plan.ends_on)
    other_workouts = create_upcoming_workouts(4, for_plan: other_plan, for_phase: other_phase)
    other_profile = create(:rider_profile, user: other_plan.user, ftp_watts: 240, intervals_icu_api_key: "other-api-key")
    stale = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 10)
    other_stale = create(:planned_workout, :structured, training_plan: other_plan, plan_phase: other_phase, scheduled_on: Date.current + 10)
    own_linked = create(:intervals_icu_sync, planned_workout: stale)
    other_linked = create(:intervals_icu_sync, planned_workout: other_stale)
    stale.update!(status: :missed)
    other_stale.update!(status: :missed)
    own_detached = create(:intervals_icu_sync, planned_workout: nil, user: plan.user, external_id: "cyclefar-workout-deleted-own")
    other_detached = create(:intervals_icu_sync, planned_workout: nil, user: other_plan.user, external_id: "cyclefar-workout-deleted-other")

    result = described_class.new(plan: plan, profile: profile, client: client).call

    expect(result).to have_attributes(synced_count: 4, removed_count: 2)
    expect(client.upserts.sole.map { |event| event.fetch(:external_id) }).to eq(workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
    expect(client.deletions.sole).to match_array([ own_linked.external_id, own_detached.external_id ])
    expect(IntervalsIcuSync.where(id: [ other_linked.id, other_detached.id ]).count).to eq(2)

    other_client = FakeClient.new
    other_result = described_class.new(plan: other_plan, profile: other_profile, client: other_client).call
    expect(other_result).to have_attributes(synced_count: 4, removed_count: 2)
    expect(other_client.upserts.sole.map { |event| event.fetch(:external_id) }).to eq(other_workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
    expect(other_client.deletions.sole).to match_array([ other_linked.external_id, other_detached.external_id ])
    expect(IntervalsIcuSync.where(user: plan.user).pluck(:external_id)).to match_array(workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
  end

  it "uses each rider's API key and all eligible events with stubbed HTTP" do
    workouts = create_upcoming_workouts(4)
    other_plan = create(:training_plan, starts_on: Date.current, ends_on: Date.current + 30)
    other_phase = create(:plan_phase, training_plan: other_plan, starts_on: other_plan.starts_on, ends_on: other_plan.ends_on)
    other_workouts = create_upcoming_workouts(4, for_plan: other_plan, for_phase: other_phase)
    other_profile = create(:rider_profile, user: other_plan.user, intervals_icu_api_key: "other-api-key")
    first_connection = SyncRecordingConnection.new
    other_connection = SyncRecordingConnection.new
    first_client = IntervalsIcu::Client.new(api_key: profile.intervals_icu_api_key, connection_factory: ->(_) { first_connection })
    other_client = IntervalsIcu::Client.new(api_key: other_profile.intervals_icu_api_key, connection_factory: ->(_) { other_connection })

    described_class.new(plan: plan, profile: profile, client: first_client).call
    described_class.new(plan: other_plan, profile: other_profile, client: other_client).call

    expect(Base64.strict_decode64(first_connection.requests.first["Authorization"].delete_prefix("Basic "))).to eq("API_KEY:test-api-key")
    expect(Base64.strict_decode64(other_connection.requests.first["Authorization"].delete_prefix("Basic "))).to eq("API_KEY:other-api-key")
    expect(JSON.parse(first_connection.requests.first.body).pluck("external_id")).to eq(workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
    expect(JSON.parse(other_connection.requests.first.body).pluck("external_id")).to eq(other_workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
  end

  it "rejects a profile belonging to another rider before making API calls" do
    other_profile = create(:rider_profile, intervals_icu_api_key: "other-api-key")
    create_upcoming_workouts(1)

    expect { described_class.new(plan: plan, profile: other_profile, client: client).call }.to raise_error(ArgumentError, /plan owner/)
    expect(client.upserts).to be_empty
    expect(client.deletions).to be_empty
  end

  it "rejects mismatched linked metadata before upserting an event" do
    workout = create_upcoming_workouts(1).sole
    sync = create(:intervals_icu_sync, planned_workout: workout)
    sync.update_columns(user_id: create(:user).id)

    expect { described_class.new(plan: plan, profile: profile, client: client).call }.to raise_error(IntervalsIcu::Client::RequestError, /owner/)
    expect(client.upserts).to be_empty
    expect(client.deletions).to be_empty
  end

  it "keeps local metadata for a retry when remote cleanup fails" do
    workouts = create_upcoming_workouts(2)
    detached = create(:intervals_icu_sync, planned_workout: nil, user: plan.user, external_id: "cyclefar-workout-deleted-own")
    allow(client).to receive(:delete_events).and_raise(IntervalsIcu::Client::RequestError, "temporary failure")

    expect { described_class.new(plan: plan, profile: profile, client: client).call }.to raise_error(described_class::PartialSyncError)
    expect(IntervalsIcuSync.pluck(:external_id)).to match_array([ detached.external_id, *workouts.map { |workout| "cyclefar-workout-#{workout.id}" } ])
    expect(IntervalsIcuSync.where(planned_workout: workouts).pluck(:last_synced_at)).to all(be_present)

    retry_client = FakeClient.new
    result = described_class.new(plan: plan, profile: profile, client: retry_client).call
    expect(result).to have_attributes(synced_count: 2, removed_count: 1)
    expect(retry_client.deletions.sole).to eq([ detached.external_id ])
    expect(IntervalsIcuSync.pluck(:external_id)).to match_array(workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
  end

  %w[missed completed past_moved deleted].each do |change|
    it "CYF-14 removes a #{change} workout's owned calendar event with stubbed HTTP and preserves local history" do
      workouts = create_upcoming_workouts(3)
      connection = SyncRecordingConnection.new
      http_client = IntervalsIcu::Client.new(api_key: profile.intervals_icu_api_key, connection_factory: ->(_) { connection })
      sync = -> { described_class.new(plan: plan, profile: profile, client: http_client).call }
      sync.call
      source = workouts.first
      external_id = source.intervals_icu_sync.external_id

      case change
      when "missed"
        source.update!(status: :missed)
      when "completed"
        Adaptations::CompletionRecorder.new(workout: source, rpe: 4, completion_quality: :as_planned).call
      when "past_moved"
        Workouts::Mover.new(source).move_to!(destination: Date.current - 1)
      when "deleted"
        source.destroy!
      end
      history = source.reload.attributes unless change == "deleted"
      steps = source.workout_steps.reload.map(&:attributes) unless change == "deleted"
      feedback = source.workout_feedback&.attributes unless change == "deleted"

      expect(sync.call).to have_attributes(synced_count: 2, removed_count: 1)
      deletion = connection.requests.find { |request| request.method == "PUT" }
      expect(deletion.path).to eq("/api/v1/athlete/0/events/bulk-delete")
      expect(JSON.parse(deletion.body)).to eq([ { "external_id" => external_id } ])
      expect(IntervalsIcuSync.where(external_id: external_id)).not_to exist
      expect(sync.call).to have_attributes(synced_count: 2, removed_count: 0)
      expect(connection.requests.count { |request| request.method == "PUT" }).to eq(1)
      expect(connection.requests.map(&:path)).to all(match(%r{\A/api/v1/athlete/0/events/bulk}))
      unless change == "deleted"
        expect(source.reload.attributes).to eq(history)
        expect(source.workout_steps.reload.map(&:attributes)).to eq(steps)
        expect(source.workout_feedback&.reload&.attributes).to eq(feedback)
      end
    end
  end

  it "cleans up the rider's previous plan events without rewriting completed history" do
    old_plan = plan
    source = create_upcoming_workouts(1).sole
    described_class.new(plan: old_plan, profile: profile, client: client).call
    Adaptations::CompletionRecorder.new(workout: source, rpe: 4, completion_quality: :as_planned).call
    old_plan.update!(status: :archived)
    new_plan = create(:training_plan, user: old_plan.user)
    history = source.reload.attributes

    result = described_class.new(plan: new_plan, profile: profile, client: client).call

    expect(result).to have_attributes(synced_count: 0, removed_count: 1)
    expect(client.deletions.last).to eq([ "cyclefar-workout-#{source.id}" ])
    expect(source.reload.attributes).to eq(history)
  end

  it "updates a moved eligible workout using the same external identity" do
    workouts = create_upcoming_workouts(2)
    described_class.new(plan: plan, profile: profile, client: client).call
    original_sync = workouts.first.intervals_icu_sync
    workouts.first.update!(scheduled_on: Date.current + 3)

    described_class.new(plan: plan, profile: profile, client: client).call

    moved_payload = client.upserts.last.find { |event| event.fetch(:external_id) == original_sync.external_id }
    expect(moved_payload.fetch(:start_date_local)).to eq("#{Date.current + 3}T00:00:00")
    expect(workouts.first.reload.intervals_icu_sync.id).to eq(original_sync.id)
    expect(client.deletions.flatten).to be_empty
  end

  it "retains uncertain upsert identities for cleanup after workouts change before retry" do
    workouts = create_upcoming_workouts(2)
    connection = SyncRecordingConnection.new
    allow(connection).to receive(:request).and_raise(Net::ReadTimeout)
    http_client = IntervalsIcu::Client.new(api_key: profile.intervals_icu_api_key, connection_factory: ->(_) { connection })

    expect { described_class.new(plan: plan, profile: profile, client: http_client).call }.to raise_error(IntervalsIcu::Client::RequestError)
    expect(connection).to have_received(:request).twice
    expect(IntervalsIcuSync.where(planned_workout: workouts).count).to eq(2)
    expect(IntervalsIcuSync.pluck(:intervals_event_id, :last_synced_at, :payload_digest)).to eq([ [ nil, nil, nil ], [ nil, nil, nil ] ])
    workouts.first.update!(status: :missed)
    workouts.last.destroy!

    result = described_class.new(plan: plan, profile: profile, client: client).call

    expect(result).to have_attributes(synced_count: 0, removed_count: 2)
    expect(client.deletions.sole).to match_array(workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
    expect(IntervalsIcuSync.where(user: plan.user)).not_to exist
  end

  it "retains confirmed upserts and stale metadata when HTTP cleanup fails, even if the next set changes" do
    workouts = create_upcoming_workouts(3)
    connection = SyncRecordingConnection.new
    http_client = IntervalsIcu::Client.new(api_key: profile.intervals_icu_api_key, connection_factory: ->(_) { connection })
    sync = -> { described_class.new(plan: plan, profile: profile, client: http_client).call }
    sync.call
    old_metadata = workouts.first.intervals_icu_sync.attributes
    workouts.first.update!(status: :missed)
    allow(connection).to receive(:request).and_wrap_original do |original, request|
      request.method == "PUT" ? SyncRecordingConnection::Response.new("503", "failure") : original.call(request)
    end

    expect { sync.call }.to raise_error(described_class::PartialSyncError, /cleanup failed.*Sync again/)
    expect(workouts.first.reload.intervals_icu_sync.attributes).to eq(old_metadata)
    expect(workouts.last.reload.intervals_icu_sync).to have_attributes(intervals_event_id: 101, last_synced_at: be_present, payload_digest: be_present)
    workouts.last.update!(status: :missed)
    allow(connection).to receive(:request).and_call_original

    expect(sync.call).to have_attributes(synced_count: 1, removed_count: 2)
    expect(JSON.parse(connection.requests.last.body).pluck("external_id")).to match_array([ workouts.first, workouts.last ].map { |workout| "cyclefar-workout-#{workout.id}" })
    expect(sync.call).to have_attributes(synced_count: 1, removed_count: 0)
  end

  def create_upcoming_workouts(count, for_plan: plan, for_phase: phase)
    count.times.map do |index|
      create(:planned_workout, :structured, training_plan: for_plan, plan_phase: for_phase, scheduled_on: Date.current + index + 1)
    end
  end
end
