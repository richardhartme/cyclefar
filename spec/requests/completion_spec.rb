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
end
