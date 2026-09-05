require "rails_helper"

RSpec.describe "Time off", type: :request do
  let(:plan) { create(:training_plan, starts_on: Date.current - 7, ends_on: Date.current + 70) }
  let!(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }
  let!(:template) { create(:availability_template, training_plan: plan, effective_from: plan.starts_on) }

  before do
    create(:availability_slot, availability_template: template, weekday: 2, duration_minutes: 60, intent: :intervals)
  end

  it "OFF-001 adds and removes a time-off period from the calendar" do
    get new_time_off_period_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add time off", "Easier return days")

    starts_on = Date.current.next_occurring(:tuesday)
    post time_off_periods_path, params: { time_off_period: { starts_on: starts_on, ends_on: starts_on + 2, reason: "recovery", return_ramp_days: 7 } }

    expect(response).to redirect_to(root_path)
    period = plan.time_off_periods.sole
    expect(period).to be_recovery
    expect(period.return_ramp_days).to eq(7)

    get root_path
    expect(response.body).to include("Time off", "Recovery")
    delete time_off_period_path(period)
    expect(response).to redirect_to(root_path)
    expect(plan.time_off_periods.reload).to be_empty
  end
end
