require "rails_helper"

RSpec.describe IntervalsIcu::SyncNextTwo do
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

  let(:plan) { create(:training_plan, starts_on: Date.current - 7, ends_on: Date.current + 30) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }
  let(:profile) { create(:rider_profile, user: plan.user, ftp_watts: 300, intervals_icu_api_key: "test-api-key") }
  let(:client) { FakeClient.new }

  it "ICU-001 syncs exactly the next two upcoming structured workouts with the current FTP" do
    workouts = create_upcoming_workouts(3)

    result = described_class.new(plan: plan, profile: profile, client: client).call

    expect(result).to have_attributes(synced_count: 2, removed_count: 0)
    expect(client.upserts.sole.map { |event| event.fetch(:external_id) }).to eq(workouts.first(2).map { |workout| "cyclefar-workout-#{workout.id}" })
    expect(client.upserts.sole.map { |event| event.fetch(:icu_ftp) }).to eq([ 300, 300 ])
    expect(IntervalsIcuSync.pluck(:external_id)).to match_array(workouts.first(2).map { |workout| "cyclefar-workout-#{workout.id}" })
  end

  it "upserts repeat syncs without creating duplicate local metadata" do
    create_upcoming_workouts(2)

    2.times { described_class.new(plan: plan, profile: profile, client: client).call }

    expect(IntervalsIcuSync.count).to eq(2)
    expect(client.upserts.map { |events| events.map { |event| event.fetch(:external_id) } }.uniq.size).to eq(1)
  end

  it "removes an owned event when a synced workout moves outside the next two" do
    workouts = create_upcoming_workouts(3)
    described_class.new(plan: plan, profile: profile, client: client).call
    moved_external_id = "cyclefar-workout-#{workouts.first.id}"
    workouts.first.update!(scheduled_on: Date.current + 10)

    result = described_class.new(plan: plan, profile: profile, client: client).call

    expect(result).to have_attributes(synced_count: 2, removed_count: 1)
    expect(client.deletions.last).to eq([ moved_external_id ])
    expect(IntervalsIcuSync.where(external_id: moved_external_id)).not_to exist
  end

  it "removes an owned event when its planned workout is deleted" do
    workouts = create_upcoming_workouts(3)
    described_class.new(plan: plan, profile: profile, client: client).call
    deleted_external_id = "cyclefar-workout-#{workouts.first.id}"
    workouts.first.destroy!

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
    profile.intervals_icu_api_key = nil

    expect { described_class.new(plan: plan, profile: profile, client: client).call }.to raise_error(IntervalsIcu::Client::RequestError, /Add an Intervals.icu API key/)
    expect(client.upserts).to be_empty
  end

  it "reconciles only the current rider's linked and detached sync records" do
    workouts = create_upcoming_workouts(2)
    other_plan = create(:training_plan, starts_on: Date.current, ends_on: Date.current + 30)
    other_phase = create(:plan_phase, training_plan: other_plan, starts_on: other_plan.starts_on, ends_on: other_plan.ends_on)
    other_workouts = create_upcoming_workouts(2, for_plan: other_plan, for_phase: other_phase)
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

    expect(result).to have_attributes(synced_count: 2, removed_count: 2)
    expect(client.upserts.sole.map { |event| event.fetch(:external_id) }).to eq(workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
    expect(client.deletions.sole).to match_array([ own_linked.external_id, own_detached.external_id ])
    expect(IntervalsIcuSync.where(id: [ other_linked.id, other_detached.id ]).count).to eq(2)

    other_client = FakeClient.new
    other_result = described_class.new(plan: other_plan, profile: other_profile, client: other_client).call
    expect(other_result).to have_attributes(synced_count: 2, removed_count: 2)
    expect(other_client.upserts.sole.map { |event| event.fetch(:external_id) }).to eq(other_workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
    expect(other_client.deletions.sole).to match_array([ other_linked.external_id, other_detached.external_id ])
    expect(IntervalsIcuSync.where(user: plan.user).pluck(:external_id)).to match_array(workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
  end

  it "uses each rider's API key and next-two events with stubbed HTTP" do
    workouts = create_upcoming_workouts(2)
    other_plan = create(:training_plan, starts_on: Date.current, ends_on: Date.current + 30)
    other_phase = create(:plan_phase, training_plan: other_plan, starts_on: other_plan.starts_on, ends_on: other_plan.ends_on)
    other_workouts = create_upcoming_workouts(2, for_plan: other_plan, for_phase: other_phase)
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

  it "updates a moved workout still in the next two using the same external identity" do
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
