require "rails_helper"

RSpec.describe "Workout completion", type: :request do
  let(:user) { create(:user) }
  before { sign_in_as(user) }

  let(:plan) { create(:training_plan, user: user, starts_on: Date.current - 7, ends_on: Date.current + 70) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:workout) { create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, subtype: :threshold, intent: :threshold, scheduled_on: Date.current + 1) }

  it "FBK-001 records manual completion from the workout detail" do
    post complete_planned_workout_path(workout), params: { rpe: 8, completion_quality: "as_planned" }
    expect(response).to redirect_to(root_path)
    expect(workout.reload).to be_completed
    expect(workout.workout_feedback).to have_attributes(rpe: 8, completion_quality: "as_planned")
  end

  it "CAL-004 shows awaiting status without auto-marking a past workout missed" do
    workout.update_column(:scheduled_on, Date.current - 1)
    get root_path
    expect(response.body).to include("Awaiting status")
    expect(workout.reload).to be_planned
  end

  %i[workout opener].each do |kind|
    it "FBK-001/FBK-003 opens and completes an overdue #{kind} outline without rewriting other workouts" do
      overdue = create(
        :planned_workout,
        training_plan: plan,
        plan_phase: phase,
        kind: kind,
        scheduled_on: Date.current - 3,
        duration_minutes: kind == :opener ? 30 : 60)
      other = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 2)
      future = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 2)
      get root_path
      expect(overdue.reload).to be_outline
      expect(response.body).to include("Awaiting status")
      # Ordinary calendar loading may materialise future workouts; opening
      # one overdue outline must leave that resulting calendar unchanged.
      before = [ other, future ].map { |item| item.reload.attributes }

      get planned_workout_path(overdue)

      expect(response).to have_http_status(:ok)
      expect(overdue.reload).to be_structured
      html = Nokogiri::HTML(response.body)
      form = html.at_css("form[action='#{complete_planned_workout_path(overdue)}']")
      expect(form).to be_present
      expect(form.text).to include("Mark completed", "RPE", "Completion quality")
      expect(form.at_css("input[type='submit']")["value"]).to eq("Save completion")
      expect([ other, future ].map { |item| item.reload.attributes }).to eq(before)
      steps = overdue.workout_steps.map(&:attributes)
      get planned_workout_path(overdue)
      expect(overdue.workout_steps.reload.map(&:attributes)).to eq(steps)

      post complete_planned_workout_path(overdue), params: { rpe: 4, completion_quality: "as_planned" }

      expect(response).to redirect_to(root_path)
      expect(overdue.reload).to be_completed
      expect(overdue.workout_steps.reload.map(&:attributes)).to eq(steps)
      expect(overdue.workout_feedback).to have_attributes(rpe: 4, completion_quality: "as_planned")
      follow_redirect!
      expect(response.body).to include("Completed")
      get planned_workout_path(overdue)
      expect(Nokogiri::HTML(response.body).at_css("form[action='#{complete_planned_workout_path(overdue)}']")).to be_nil
    end
  end

  it "FBK-001 exposes completion for a structured opener" do
    phase
    opener = Workouts::Creator.new(plan).create!(scheduled_on: Date.current, subtype: :opener, duration_minutes: 45)
    get planned_workout_path(opener)
    expect(Nokogiri::HTML(response.body).at_css("form[action='#{complete_planned_workout_path(opener)}']")).to be_present
    post complete_planned_workout_path(opener), params: { rpe: 5, completion_quality: "as_planned" }
    expect(response).to redirect_to(root_path)
    expect(opener.reload).to be_completed
  end

  it "USR-004 prevents another rider from opening or completing an overdue outline" do
    foreign_plan = create(:training_plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    foreign_phase = create(:plan_phase, training_plan: foreign_plan, ends_on: foreign_plan.ends_on)
    foreign = create(:planned_workout, training_plan: foreign_plan, plan_phase: foreign_phase, scheduled_on: Date.current - 1)
    before = foreign.attributes
    get planned_workout_path(foreign)
    expect(response).to have_http_status(:not_found)
    post complete_planned_workout_path(foreign), params: { rpe: 4, completion_quality: "as_planned" }
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.attributes).to eq(before)
    expect(foreign.workout_steps).to be_empty
    expect(foreign.workout_feedback).to be_nil
  end
end
