require "rails_helper"

RSpec.describe "LOAD-002 weekly load guidance", type: :request, generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:user) { create(:user) }
  let(:plan) { create(:training_plan, user: user, starts_on: today - 21, ends_on: today + 62, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }

  before do
    travel_to today
    sign_in_as(user)
  end

  it "links a load warning to the prefilled week and clears it after a load-reducing change" do
    template = create(:availability_template, training_plan: plan, effective_from: plan.starts_on)
    create(:availability_slot, availability_template: template, weekday: 3, duration_minutes: 180, intent: :threshold)
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: today - 14)
    history = [ completed.attributes, completed.workout_steps.map(&:attributes) ]
    reference = generated_workout(plan: plan, phase: phase, date: today, duration: 60, subtype: :endurance)
    affected = generated_workout(plan: plan, phase: phase, date: today + 30, duration: 180)
    week_start = affected.scheduled_on.beginning_of_week
    foreign_plan = create(:training_plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    foreign_phase = create(:plan_phase, training_plan: foreign_plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    foreign_workout = generated_workout(plan: foreign_plan, phase: foreign_phase, date: today + 37, duration: 600)

    get root_path

    html = Nokogiri::HTML(response.body)
    guidance = html.at_css('section[aria-labelledby="load-guidance-heading"]')
    expect(guidance.text).to include("1 week above", "advisory warnings", "reduce training minutes", "Projected TSS", "Target TSS")
    expect(guidance.css("tbody tr").size).to eq(1)
    row = guidance.at_css("tbody tr")
    expect(row.text).to include(week_start.to_fs(:long), format("%.1f", affected.estimated_tss), format("%.1f", reference.estimated_tss.to_f * 1.08))
    calendar_link = row.css("a").find { |link| link.text == "View in calendar" }
    expect(html.at_css(calendar_link["href"])).to be_present
    edit_link = row.css("a").find { |link| link.text == "Edit this week" }
    get edit_link["href"]

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("#effective_from")["value"]).to eq(week_start.iso8601)
    expect(html.at_css("#availability_day_3")["checked"]).to be_present
    expect(html.at_css("#availability_duration_3")["value"]).to eq("180")
    expect(html.at_css("#availability_intent_3 option[selected]")["value"]).to eq("threshold")

    post availability_change_path,
      params: {
      scope: "one_week", effective_from: week_start.iso8601,
      slots: { "3" => { weekday: "3", enabled: "1", duration_minutes: "60", intent: "endurance" } }
    }
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to be_nil
    follow_redirect!
    expect(response.body).not_to include("load-guidance-heading")
    expect(plan.planned_workouts.find_by!(scheduled_on: today + 30)).to have_attributes(duration_minutes: 60, intent: "endurance")
    expect([ completed.reload.attributes, completed.workout_steps.reload.map(&:attributes) ]).to eq(history)
    expect(foreign_workout.reload.duration_minutes).to eq(600)
    expect(template.reload.effective_until).to be_nil
  end

  it "groups several future warnings into one disclosure and omits past warnings" do
    generated_workout(plan: plan, phase: phase, date: today - 21, duration: 30, subtype: :endurance)
    generated_workout(plan: plan, phase: phase, date: today - 14, duration: 120, subtype: :threshold)
    generated_workout(plan: plan, phase: phase, date: today, duration: 30, subtype: :endurance)
    generated_workout(plan: plan, phase: phase, date: today + 28, duration: 180, subtype: :threshold)
    generated_workout(plan: plan, phase: phase, date: today + 35, duration: 600, subtype: :threshold)

    get root_path

    html = Nokogiri::HTML(response.body)
    guidance = html.css('section[aria-labelledby="load-guidance-heading"]')
    expect(guidance.size).to eq(1)
    expect(guidance.text).to include("2 weeks above")
    expect(guidance.css("details summary").text).to eq("Review affected weeks")
    expect(guidance.css("tbody tr").size).to eq(2)
    expect(guidance.text).not_to include((today - 14).to_fs(:long))
  end
end
