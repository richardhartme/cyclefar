require "rails_helper"

RSpec.describe "Planned workouts", type: :request do
  let(:plan) { create(:training_plan, starts_on: Date.current - 7, ends_on: Date.current + 70) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:workout) { create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: plan.starts_on + 1) }

  it "WKO-001 renders detail without an individual-step editing endpoint" do
    get planned_workout_path(workout)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(workout.name, "Steps", "Adjust workout", "Move workout")
    expect { Rails.application.routes.recognize_path("/planned_workouts/#{workout.id}", method: :patch) }.to raise_error(ActionController::RoutingError)
  end

  it "WKO-001 renders the workout detail as a navigable page" do
    get planned_workout_path(workout)

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("h1").text).to eq(workout.name)
    expect(html.css("a").find { |link| link.text == "Back to calendar" }["href"]).to eq(root_path)
  end

  it "WKO-001 provides a useful detail state before a workout is structured" do
    outline = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: plan.starts_on + 2)

    get root_path
    calendar_link = Nokogiri::HTML(response.body).css("a").find { |link| link.text == outline.name }
    expect(calendar_link["href"]).to eq(planned_workout_path(outline))

    get planned_workout_path(outline)

    expect(response.body).to include("detailed structure for this workout will be generated")
    expect(response.body).not_to include("Adjust workout")
  end

  it "WKO-004 rejects shorter below 30 minutes through the action" do
    short = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, duration_minutes: 30, scheduled_on: plan.starts_on + 2)
    post shuffle_planned_workout_path(short), params: { action_kind: "shorter" }
    expect(response).to redirect_to(planned_workout_path(short))
    expect(flash[:alert]).to include("below 30")
    expect(short.reload.duration_minutes).to eq(30)
  end

  it "WKO-006 moves only to an empty date inside the plan" do
    post move_planned_workout_path(workout), params: { scheduled_on: (plan.starts_on + 3).iso8601 }
    expect(response).to redirect_to(root_path)
    expect(workout.reload.scheduled_on).to eq(plan.starts_on + 3)
    other = create(:planned_workout, training_plan: plan, plan_phase: phase, scheduled_on: plan.starts_on + 4)
    post move_planned_workout_path(workout), params: { scheduled_on: other.scheduled_on.iso8601 }
    expect(flash[:alert]).to include("already has a workout")
    expect(workout.reload.scheduled_on).to eq(plan.starts_on + 3)
  end

  it "WKO-006 preserves completed workout history when a move is requested" do
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: plan.starts_on + 5)
    post move_planned_workout_path(completed), params: { scheduled_on: (plan.starts_on + 6).iso8601 }
    expect(flash[:alert]).to include("Completed workouts cannot be moved")
    expect(completed.reload.scheduled_on).to eq(plan.starts_on + 5)
  end

  it "MIS-001 removes a past workout after the rider resolves it as missed" do
    past = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 1)

    post miss_planned_workout_path(past), params: { resolution: "leave_unchanged" }

    expect(response).to redirect_to(root_path)
    expect { past.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "FTP-001 presents an assessment action and records a completed FTP test" do
    ftp_test = create(:planned_workout, :ftp_test, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 2)

    get planned_workout_path(ftp_test)
    expect(response.body).to include("preferred FTP assessment protocol", "Test done — update FTP")
    post complete_test_planned_workout_path(ftp_test)

    expect(response).to redirect_to(settings_path)
    expect(ftp_test.reload).to be_completed
    expect(ftp_test.completed_at).to be_present
  end

  it "SET-001 displays current FTP watt targets for planned workouts and snapshots for completed workouts" do
    Settings::Update.new(profile: RiderProfile.current, attributes: { ftp_watts: 300 }).call
    planned = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 2)
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 3)

    get planned_workout_path(planned)
    expect(response.body).to include("FTP basis: 300 W", "180–210 W")
    get planned_workout_path(completed)
    expect(response.body).to include("FTP basis: 260 W", "156–182 W")
  end
end
