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
    expect(response.body).to include("Add time off", "Event", "Easier return days")

    starts_on = Date.current.next_occurring(:tuesday)
    post time_off_periods_path, params: { time_off_period: { starts_on: starts_on, ends_on: starts_on + 2, reason: "recovery", name: "France", return_ramp_days: 7 } }

    expect(response).to redirect_to(root_path)
    period = plan.time_off_periods.sole
    expect(period).to be_recovery
    expect(period.name).to eq("France")
    expect(period.return_ramp_days).to eq(7)

    get root_path
    time_off_card = Nokogiri::HTML(response.body).css("article").find { |article| article.text.include?("France") }
    expect(time_off_card.at_css("strong").text).to eq("France")
    expect(time_off_card.text).to include("Recovery")
    delete time_off_period_path(period)
    expect(response).to redirect_to(root_path)
    expect(plan.time_off_periods.reload).to be_empty
  end

  it "OFF-001 adds Event time off without an easier return period" do
    starts_on = Date.current.next_occurring(:tuesday)

    post time_off_periods_path, params: { time_off_period: { starts_on: starts_on, ends_on: starts_on, reason: "event" } }

    expect(response).to redirect_to(root_path)
    expect(plan.time_off_periods.sole).to have_attributes(reason: "event", return_ramp_days: nil)

    get root_path
    time_off_card = Nokogiri::HTML(response.body).css("article").find { |article| article.text.include?("Event") }
    expect(time_off_card).to be_nil
    time_off_card = Nokogiri::HTML(response.body).css("article").find { |article| article.text.include?("Time off") }
    expect(time_off_card.at_css("strong").text).to eq("Time off")
  end
end
