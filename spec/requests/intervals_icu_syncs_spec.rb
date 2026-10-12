require "rails_helper"

RSpec.describe "Intervals.icu sync", type: :request do
  let(:user) { create(:user) }
  before { sign_in_as(user) }

  [ 0, 1, 4 ].each do |count|
    it "reports the actual count after syncing #{count} eligible workouts" do
      plan = create(:training_plan, user: user, starts_on: Date.current, ends_on: Date.current + 30)
      phase = create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
      create(:rider_profile, user: user, intervals_icu_api_key: "test-key")
      workouts = [ 0, 1, 3, 20 ].first(count).map do |days|
        create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + days)
      end
      client = instance_double(IntervalsIcu::Client)
      allow(IntervalsIcu::Client).to receive(:new).with(api_key: "test-key").and_return(client)
      allow(client).to receive(:upsert_events) do |payloads|
        expect(payloads.pluck(:external_id)).to eq(workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
        payloads.map.with_index { |payload, index| { "external_id" => payload.fetch(:external_id), "id" => index + 100 } }
      end
      allow(client).to receive(:delete_events)

      post intervals_icu_sync_path

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Synced #{count} workout#{'s' unless count == 1} to Intervals.icu.")
      if count.zero?
        expect(client).not_to have_received(:upsert_events)
      else
        expect(client).to have_received(:upsert_events).once
      end
    end
  end

  it "ICU-001 shows a manual sync action and reports a missing API key" do
    plan = create(:training_plan, user: user)
    create(:plan_phase, training_plan: plan)

    get root_path
    expect(response.body).to include("Sync workouts to Intervals.icu")

    post intervals_icu_sync_path
    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("Add an Intervals.icu API key in Settings before syncing")
  end
end
