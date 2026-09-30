require "rails_helper"

RSpec.describe "USR-008 two-rider isolation", type: :request do
  before { travel_to Time.zone.local(2026, 9, 28, 12) }
  after { travel_back }

  def plan_for(user)
    plan = create(:training_plan, user: user, starts_on: Date.current - 7, ends_on: Date.current + 70)
    phase = create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    template = create(:availability_template, training_plan: plan, effective_from: plan.starts_on)
    create(:availability_slot, availability_template: template, weekday: 2, duration_minutes: 60, intent: :endurance)
    [ plan, phase ]
  end

  it "keeps feedback, adaptation, schedule, FTP and archived history inside the signed-in account" do
    first = create(:user)
    second = create(:user)
    first_profile = create(:rider_profile, user: first, ftp_watts: 260)
    second_profile = create(:rider_profile, user: second, ftp_watts: 310, intervals_icu_api_key: "second-rider-key")
    first_plan, first_phase = plan_for(first)
    second_plan, second_phase = plan_for(second)
    completed = create(:planned_workout, :structured, training_plan: first_plan, plan_phase: first_phase, scheduled_on: Date.current + 1, intent: :intervals, subtype: :threshold)
    adaptation_target = create(:planned_workout, :structured, training_plan: first_plan, plan_phase: first_phase, scheduled_on: Date.current + 3, intent: :intervals, subtype: :threshold, progression_level: 2)
    missed = create(:planned_workout, :structured, training_plan: first_plan, plan_phase: first_phase, scheduled_on: Date.current - 1)
    second_workout = create(:planned_workout, :structured, training_plan: second_plan, plan_phase: second_phase, scheduled_on: Date.current + 1, name: "Private second-rider workout")
    second_history = create(:planned_workout, :completed, training_plan: second_plan, plan_phase: second_phase, scheduled_on: Date.current - 2)
    second_workout_before = second_workout.attributes.deep_dup
    second_history_before = second_history.attributes.deep_dup
    second_steps_before = second_workout.workout_steps.map(&:attributes)

    sign_in_as(first)
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(second_workout.name)
    get planned_workout_path(second_workout)
    expect(response).to have_http_status(:not_found)

    post complete_planned_workout_path(completed), params: { rpe: 9, completion_quality: "struggled_completed" }
    expect(response).to redirect_to(root_path)
    expect(completed.reload).to be_completed
    expect(completed.workout_feedback).to have_attributes(rpe: 9, completion_quality: "struggled_completed")
    snapshot = completed.completed_target_snapshot.deep_dup
    steps = completed.workout_steps.map(&:attributes)
    proposal = first_plan.adaptation_proposals.sole
    post accept_adaptation_proposal_path(proposal)
    expect(response).to redirect_to(root_path)
    expect(first_plan.adaptation_proposals).to be_empty
    expect(adaptation_target.reload.progression_level).to eq(1)

    post miss_planned_workout_path(missed), params: { resolution: "leave_unchanged" }
    expect(missed.reload).to be_missed
    patch settings_path, params: { rider_profile: { ftp_watts: 280 } }
    expect(response).to redirect_to(settings_path)
    expect(first_profile.reload.ftp_watts).to eq(280)
    expect(completed.reload.completed_target_snapshot).to eq(snapshot)
    expect(completed.workout_steps.map(&:attributes)).to eq(steps)

    post availability_change_path,
      params: {
        scope: "from_date", effective_from: (Date.current + 7).iso8601,
        slots: { "2" => { weekday: "2", enabled: "1", duration_minutes: "75", intent: "endurance" } }
      }
    expect(response).to redirect_to(root_path)
    post time_off_periods_path, params: { time_off_period: { starts_on: Date.current + 14, ends_on: Date.current + 15, reason: "holiday" } }
    expect(response).to redirect_to(root_path)
    expect(first_plan.time_off_periods.count).to eq(1)

    delete training_plan_path
    expect(response).to redirect_to(root_path)
    expect(first_plan.reload).to be_archived
    expect(completed.reload.completed_target_snapshot).to eq(snapshot)
    get planned_workout_path(completed)
    expect(response).to have_http_status(:ok)

    delete session_path
    sign_in_as(second)
    get planned_workout_path(completed)
    expect(response).to have_http_status(:not_found)
    get planned_workout_path(second_workout)
    expect(response).to have_http_status(:ok)
    get settings_path
    expect(Nokogiri::HTML(response.body).at_css('input[name="rider_profile[ftp_watts]"]')["value"]).to eq("310")
    expect(second_plan.reload).to be_active
    expect(second_profile.reload).to have_attributes(ftp_watts: 310, intervals_icu_api_key: "second-rider-key")
    expect(second_profile.ftp_readings).to be_empty
    expect(second_workout.reload.attributes).to eq(second_workout_before)
    expect(second_workout.workout_steps.map(&:attributes)).to eq(second_steps_before)
    expect(second_history.reload.attributes).to eq(second_history_before)
    expect(completed.reload.completed_target_snapshot).to eq(snapshot)
  end

  it "uses separate credentials and cleans up only the signed-in rider's detached sync records" do
    first = create(:user)
    second = create(:user)
    create(:rider_profile, user: first, ftp_watts: 260, intervals_icu_api_key: "first-rider-key")
    create(:rider_profile, user: second, ftp_watts: 310, intervals_icu_api_key: "second-rider-key")
    first_plan, first_phase = plan_for(first)
    second_plan, second_phase = plan_for(second)
    first_workouts = [ 1, 3 ].map { |days| create(:planned_workout, :structured, training_plan: first_plan, plan_phase: first_phase, scheduled_on: Date.current + days) }
    second_workouts = [ 1, 3 ].map { |days| create(:planned_workout, :structured, training_plan: second_plan, plan_phase: second_phase, scheduled_on: Date.current + days) }
    first_detached = create(:intervals_icu_sync, planned_workout: nil, user: first, external_id: "cyclefar-first-deleted")
    second_detached = create(:intervals_icu_sync, planned_workout: nil, user: second, external_id: "cyclefar-second-deleted")
    calls = []
    allow(IntervalsIcu::Client).to receive(:new) do |api_key:|
      client = instance_double(IntervalsIcu::Client)
      allow(client).to receive(:upsert_events) do |events|
        calls << [ api_key, :upsert, events.pluck(:external_id) ]
        events.map.with_index { |event, index| { "external_id" => event.fetch(:external_id), "id" => index + 100 } }
      end
      allow(client).to receive(:delete_events) do |external_ids|
        calls << [ api_key, :delete, external_ids ]
        []
      end
      client
    end

    sign_in_as(first)
    post intervals_icu_sync_path
    expect(response).to redirect_to(root_path)
    expect(calls).to include([ "first-rider-key", :upsert, first_workouts.map { |workout| "cyclefar-workout-#{workout.id}" } ])
    expect(calls).to include([ "first-rider-key", :delete, [ first_detached.external_id ] ])
    expect(IntervalsIcuSync.exists?(second_detached.id)).to be(true)

    delete session_path
    sign_in_as(second)
    post intervals_icu_sync_path
    expect(response).to redirect_to(root_path)
    expect(calls).to include([ "second-rider-key", :upsert, second_workouts.map { |workout| "cyclefar-workout-#{workout.id}" } ])
    expect(calls).to include([ "second-rider-key", :delete, [ second_detached.external_id ] ])
    expect(calls.map(&:first)).to match_array([ "first-rider-key", "first-rider-key", "second-rider-key", "second-rider-key" ])
    expect(IntervalsIcuSync.where(user: first).pluck(:external_id)).to match_array(first_workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
    expect(IntervalsIcuSync.where(user: second).pluck(:external_id)).to match_array(second_workouts.map { |workout| "cyclefar-workout-#{workout.id}" })
  end
end
