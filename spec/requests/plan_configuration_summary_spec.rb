require "rails_helper"

RSpec.describe "CYF-90 plan configuration summary", type: :request do
  let(:user) { create(:user) }
  before { sign_in_as(user) }

  def inputs(**changes)
    { goal: "increase_ftp", starts_on: "2028-01-31", plan_length: "1", ftp_watts: "260",
      progression_mode: "hard_recovery_cycle", hard_weeks_before_recovery: "3",
      availability: {
        "2" => { weekday: "2", enabled: "1", duration_minutes: "60", intent: "intervals" },
        "4" => { weekday: "4", enabled: "1", duration_minutes: "90", intent: "endurance" },
        "6" => { weekday: "6", enabled: "0", duration_minutes: "600", intent: "endurance" }
      } }.merge(changes)
  end

  def summary
    Nokogiri::HTML(response.body).at_css("#configuration-summary")
  end

  it "shows active non-event timing, recovery and normal enabled availability, matching preview after Back to edit" do
    expect {
      post summary_training_plan_path, params: { plan_configuration: inputs }
    }.not_to change(TrainingPlan, :count)

    expect(summary.text).to include("Increase FTP", "January 31, 2028", "February 28, 2028", "1 month")
    expect(summary.text).to include("2 training days", "2 h 30 min", "3 hard weeks, then one recovery week")
    expect(summary.text).to include("Normal session lengths may be reduced during recovery weeks and taper.")
    expect(summary.text).not_to include("Discipline", "600", "Target event")

    post preview_training_plan_path, params: { plan_configuration: inputs }
    follow_redirect!
    expect(response.body).to include("February 28, 2028", "3 hard weeks, then one recovery week")
    get new_training_plan_path
    expect(summary.text).to include("February 28, 2028", "2 h 30 min")
  end

  it "shows the active event discipline, target and taper without stale duration choices" do
    post summary_training_plan_path,
      params: { plan_configuration: inputs(
        goal: "event",
        plan_length: "custom",
        custom_duration_weeks: "2",
        event_name: "Trail ride",
        event_on: "2028-04-30",
        event_discipline: "mtb",
        progression_mode: "continuous",
        hard_weeks_before_recovery: "invalid") }

    expect(summary.text).to include("Prepare for an Event", "MTB", "Trail ride", "April 30, 2028")
    expect(summary.text).to include("taper", "day-before opener", "Continuous progression — no scheduled recovery weeks")
    expect(summary.text).not_to include("Custom weeks", "2 weeks", "invalid")
  end

  it "uses placeholders for incomplete active values and excludes inactive event fields" do
    post summary_training_plan_path,
      params: { plan_configuration: inputs(
        starts_on: "invalid",
        plan_length: "custom",
        custom_duration_weeks: "3",
        event_name: "Stale event",
        event_on: "2028-05-01",
        availability: { "2" => { weekday: "2", enabled: "1", duration_minutes: "bad", intent: "intervals" } }) }

    expect(summary.text).to include("Choose a valid start date", "Choose a valid start date and plan length", "Choose valid training days")
    expect(summary.text).not_to include("2028-05-01", "Stale event", "May 1, 2028", "0 h")

    post summary_training_plan_path,
      params: { plan_configuration: inputs(
        goal: "event",
        event_name: "Trail ride",
        event_on: "2028-02-10",
        event_discipline: "unknown") }
    expect(summary.text).to include("Choose a valid event date", "Choose event discipline")
    expect(summary.text).not_to include("February 10, 2028", "unknown")
  end
end
