require "rails_helper"

RSpec.describe "Training plan preview", type: :request do
  def plan_configuration(overrides = {})
    {
      goal: "increase_ftp", discipline: "road", starts_on: "2026-09-07", duration_mode: "preset", duration_months: "3",
      ftp_watts: "260", include_base: "1", progression_mode: "hard_recovery_cycle", hard_weeks_before_recovery: "3",
      availability: {
        "1" => { weekday: "1", enabled: "1", duration_minutes: "60", intent: "intervals" },
        "3" => { weekday: "3", enabled: "1", duration_minutes: "90", intent: "endurance" },
        "6" => { weekday: "6", enabled: "1", duration_minutes: "60", intent: "intervals" }
      }
    }.merge(overrides)
  end

  it "PLN-010 renders one configuration form with all plan inputs" do
    get new_training_plan_path
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("form")).to be_present
    expect(html.at_css("form")["data-turbo"]).to eq("false")
    expect(response.body).to include("Goal", "Discipline", "Timing", "Target event", "FTP (watts)", "Weekly availability", "Preview plan")
    expect(response.body).to include(
      "Balances aerobic endurance with varied intensity",
      "Prioritises threshold, VO2 Max and over-under progression",
      "Emphasises endurance volume",
      "sustained climbing efforts",
      "shape speciality sessions, taper and opener"
    )
  end

  it "PLN-013 generates and renders an in-memory preview without persisting a plan" do
    expect {
      post preview_training_plan_path, params: { plan_configuration: plan_configuration }
    }.not_to change { [ TrainingPlan.count, PlannedWorkout.count, PlanPhase.count, TargetEvent.count, AvailabilityTemplate.count ] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Plan preview", "Phase timeline", "Weekly template", "FTP assessments", "Projected weekly load", "Back to edit")
    expect(response.body).to include("Recovery week")
  end

  it "PLN-010 returns useful validation errors without generating a preview" do
    post preview_training_plan_path, params: { plan_configuration: plan_configuration(ftp_watts: "", availability: {}) }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Please correct the plan configuration", "Ftp watts can&#39;t be blank")
  end

  it "PLN-022 displays target-event taper and opener details" do
    post preview_training_plan_path, params: { plan_configuration: plan_configuration(goal: "event", event_name: "Autumn Classic", event_on: "2026-12-06", event_discipline: "road", event_expected_duration_minutes: "360") }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Target event:", "Taper and opener", "Event Opener")
  end

  it "PLN-013 / CAL-001 confirms the preview and renders a continuous persisted calendar" do
    post preview_training_plan_path, params: { plan_configuration: plan_configuration }
    expect {
      post training_plan_path
    }.to change(TrainingPlan, :count).by(1)
    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("Training calendar", "Training plan created.", "September", "November")
    expect(response.body).to include("FTP Test")
    expect(response.body).to include("Workout power profile")
    expect(Nokogiri::HTML(response.body).css("svg polygon")).not_to be_empty
    expect(TrainingPlan.active.sole.planned_workouts.structured.count).to be < TrainingPlan.active.sole.planned_workouts.count
  end
end
