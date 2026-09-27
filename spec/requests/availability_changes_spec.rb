require "rails_helper"

RSpec.describe "Availability changes", type: :request do
  before { sign_in_as(create(:user)) }

  let(:plan) { create(:training_plan, starts_on: Date.current - 7, ends_on: Date.current + 70) }
  let!(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }
  let!(:template) { create(:availability_template, training_plan: plan, effective_from: plan.starts_on) }

  before do
    create(:availability_slot, availability_template: template, weekday: 2, duration_minutes: 60, intent: :intervals)
  end

  it "SCH-001 exposes and applies the availability change form" do
    get new_availability_change_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Change availability", "This week only", "From date onward")

    post availability_change_path,
      params: {
            scope: "from_date", effective_from: (Date.current + 7).iso8601,
            slots: { "2" => { weekday: "2", enabled: "1", duration_minutes: "90", intent: "threshold" } }
          }

    expect(flash[:alert]).to be_nil
    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq("Availability updated.")
    expect(plan.availability_templates.order(:created_at).last).to be_from_date_change
  end
end
