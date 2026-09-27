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

  let(:plan) { create(:training_plan, starts_on: Date.current, ends_on: Date.current + 30) }
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

  def create_upcoming_workouts(count)
    count.times.map do |index|
      create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + index + 1)
    end
  end
end
