require "rails_helper"

RSpec.describe "FBK-002 owner-scoped progression bias", type: :request, generated_workouts: true do
  before { travel_to Date.new(2026, 10, 5) }

  it "USR-008 accepts, materialises and updates FTP privately while retaining both riders' completed history" do
    first, second = create_list(:user, 2)
    profiles = [ first, second ].zip([ 275, 410 ]).map { |user, ftp| create(:rider_profile, user: user, ftp_watts: ftp) }
    plans = [ first, second ].map do |user|
      create(
        :training_plan,
        user: user,
        starts_on: Date.current - 2,
        ends_on: Date.current + 83,
        progression_mode: :continuous,
        hard_weeks_before_recovery: nil)
    end
    phases = plans.map { |plan| create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }
    history = plans.zip(phases).map do |plan, phase|
      create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 1)
    end
    targets = plans.zip(phases).map { |plan, phase| generated_workout(plan: plan, phase: phase, date: Date.current + 1, level: 3, duration: 90) }
    outlines = plans.zip(phases).map do |plan, phase|
      create(
        :planned_workout,
        training_plan: plan,
        plan_phase: phase,
        scheduled_on: Date.current + 14,
        intent: :threshold,
        subtype: :threshold,
        progression_level: 3,
        duration_minutes: 90,
        variation_key: "standard")
    end
    proposals = plans.zip(targets, [ -1, 1 ]).map do |plan, target, bias|
      create(
        :adaptation_proposal,
        training_plan: plan,
        payload: {
                "changes" => [ { "planned_workout_id" => target.id, "progression_level" => 3 + bias } ],
                "progression_bias" => bias },
        expires_at: 7.days.from_now)
    end
    histories_before = history.map { |item| [ item.attributes, item.workout_steps.map(&:attributes), item.workout_feedback.attributes ] }
    second_before = [ plans.last.attributes, profiles.last.attributes, targets.last.attributes, outlines.last.attributes, proposals.last.attributes ]

    sign_in_as(first)
    get root_path
    expect(outlines.first.reload).to be_outline
    post accept_adaptation_proposal_path(proposals.first)
    expect(response).to redirect_to(root_path)
    travel_to Date.current + 1
    get root_path
    expect(outlines.first.reload.progression_level).to eq(2)
    expect(outlines.last.reload).to be_outline
    expect([ plans.last.reload.attributes, profiles.last.reload.attributes, targets.last.reload.attributes, outlines.last.attributes, proposals.last.reload.attributes ]).to eq(second_before)

    post accept_adaptation_proposal_path(proposals.last)
    expect(response).to have_http_status(:not_found)
    foreign_response = response.body
    post accept_adaptation_proposal_path(id: 999_999)
    expect(response).to have_http_status(:not_found)
    expect(response.body).to eq(foreign_response)

    first_steps = outlines.first.workout_steps.map(&:attributes)
    patch settings_path, params: { rider_profile: { ftp_watts: 300 } }
    get root_path
    expect(outlines.first.workout_steps.reload.map(&:attributes)).to eq(first_steps)
    expect(plans.first.reload.progression_state).to eq("intensity_bias" => -1)
    delete session_path
    sign_in_as(second)
    post accept_adaptation_proposal_path(proposals.last)
    get root_path
    expect(outlines.last.reload.progression_level).to eq(4)
    metrics = Metrics::WorkoutCalculator.new(steps: outlines.last.workout_steps, ftp_watts: 410).call
    expect(outlines.last.estimated_work_kj).to be_within(0.001).of(metrics.estimated_work_kj)
    expect(outlines.first.reload.progression_level).to eq(2)
    expect(history.map { |item| [ item.reload.attributes, item.workout_steps.map(&:attributes), item.workout_feedback.attributes ] }).to eq(histories_before)
  end
end
