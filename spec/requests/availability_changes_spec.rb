require "rails_helper"

RSpec.describe "Availability changes", type: :request do
  let(:user) { create(:user) }
  before { sign_in_as(user) }

  let(:plan) { create(:training_plan, user: user, starts_on: Date.current - 7, ends_on: Date.current + 70) }
  let!(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }
  let!(:template) { create(:availability_template, training_plan: plan, effective_from: plan.starts_on) }

  before do
    create(:availability_slot, availability_template: template, weekday: 2, duration_minutes: 60, intent: :intervals)
  end

  it "SCH-001 exposes and applies the availability change form" do
    get new_availability_change_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Change availability", "This week only", "From date onward")
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("#availability_day_2")["checked"]).to be_present
    expect(html.at_css("#availability_day_1")["checked"]).to be_nil
    expect(html.at_css("#availability_duration_2")["value"]).to eq("60")
    expect(html.at_css("#availability_intent_2 option[selected]")["value"]).to eq("intervals")

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

  it "SCH-001 prefills the requested week using its override ahead of the repeating schedule" do
    date = (Date.current + 21).beginning_of_week
    override = create(:availability_template, training_plan: plan, effective_from: date, effective_until: date + 6, source: :one_week_override)
    create(:availability_slot, availability_template: override, weekday: 4, duration_minutes: 90, intent: :endurance)

    get new_availability_change_path, params: { effective_from: date.iso8601 }

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("#effective_from")["value"]).to eq(date.iso8601)
    expect(html.at_css("#scope option[selected]")["value"]).to eq("one_week")
    expect(html.at_css("#availability_day_2")["checked"]).to be_nil
    expect(html.at_css("#availability_day_4")["checked"]).to be_present
    expect(html.at_css("#availability_duration_4")["value"]).to eq("90")
    expect(html.at_css("#availability_intent_4 option[selected]")["value"]).to eq("endurance")
  end

  it "SCH-001 uses the effective schedule on each side of a midweek availability change" do
    date = (Date.current + 21).beginning_of_week
    template.update!(effective_until: date + 2)
    changed = create(:availability_template, training_plan: plan, effective_from: date + 3, source: :from_date_change)
    create(:availability_slot, availability_template: changed, weekday: 4, duration_minutes: 120, intent: :threshold)

    get new_availability_change_path, params: { effective_from: date.iso8601 }

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("#availability_day_2")["checked"]).to be_present
    expect(html.at_css("#availability_day_4")["checked"]).to be_present
    expect(html.at_css("#availability_duration_4")["value"]).to eq("120")
  end

  it "rejects malformed or out-of-plan week links without mutating the schedule" do
    [ "invalid", (plan.ends_on + 7).iso8601 ].each do |date|
      expect { get new_availability_change_path, params: { effective_from: date } }.not_to change(AvailabilityTemplate, :count)
      expect(response).to redirect_to(new_availability_change_path)
      expect(flash[:alert]).to be_present
    end
  end
end
