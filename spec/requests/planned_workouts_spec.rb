require "rails_helper"

RSpec.describe "Planned workouts", type: :request do
  let(:plan) { create(:training_plan, starts_on: Date.current - 7, ends_on: Date.current + 70) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:workout) { create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: plan.starts_on + 1) }

  it "WKO-001 renders detail without an individual-step editing endpoint" do
    get planned_workout_path(workout)
    expect(response).to have_http_status(:ok), flash[:alert]
    expect(response.body).to include(workout.name, "Steps", "Adjust workout", "Opener", "Move workout", "Copy workout")
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

  it "WKO-008 links an empty calendar date to a form that adds a canonical workout" do
    scheduled_on = Date.current + 2
    plan
    phase

    get root_path
    calendar_link = Nokogiri::HTML(response.body).css("a").find do |link|
      link["href"] == new_planned_workout_path(scheduled_on: scheduled_on)
    end
    expect(calendar_link).to be_present

    get new_planned_workout_path(scheduled_on: scheduled_on)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add workout", scheduled_on.to_fs(:long), "Workout type")

    expect do
      post(
        planned_workouts_path,
        params: {
          scheduled_on: scheduled_on,
          subtype: "threshold",
          duration_minutes: 60
        })
    end.to change(PlannedWorkout, :count).by(1)

    expect(response).to redirect_to(root_path)
    expect(plan.planned_workouts.find_by!(scheduled_on: scheduled_on)).to have_attributes(
      subtype: "threshold",
      detail_status: "structured")
  end

  it "WKO-004 rejects shorter below 30 minutes through the action" do
    short = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, duration_minutes: 30, scheduled_on: plan.starts_on + 2)
    post shuffle_planned_workout_path(short), params: { action_kind: "shorter" }
    expect(response).to redirect_to(planned_workout_path(short))
    expect(flash[:alert]).to include("below 30")
    expect(short.reload.duration_minutes).to eq(30)
  end

  it "WKO-005 changes a workout to an opener through the detail page" do
    post change_planned_workout_path(workout), params: { subtype: "opener", duration_minutes: 45 }

    expect(response).to redirect_to(planned_workout_path(workout))
    expect(workout.reload).to have_attributes(
      kind: "opener",
      duration_minutes: 45,
      name: "Event Opener")
    proposal = plan.adaptation_proposals.sole
    expect(proposal).to be_material_change_replan

    follow_redirect!
    expect(response.body).to include("Replan upcoming workouts", "Keep rest of plan unchanged")
  end

  it "WKO-005 dismisses a material-change proposal without changing the rest of the plan" do
    other = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 2)
    original_attributes = other.attributes
    post change_planned_workout_path(workout), params: { subtype: "recovery", duration_minutes: 60 }
    proposal = plan.adaptation_proposals.sole

    delete reject_adaptation_proposal_path(proposal)

    expect(response).to redirect_to(root_path)
    expect(other.reload.attributes).to eq(original_attributes)
    expect(AdaptationProposal).not_to exist(proposal.id)
  end

  it "WKO-005 accepts a material-change proposal and preserves the changed workout" do
    source = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 1)
    replaceable = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 3)
    template = create(:availability_template, training_plan: plan, effective_from: plan.starts_on)
    create(:availability_slot, availability_template: template, weekday: (Date.current + 3).cwday, duration_minutes: 75, intent: :endurance)
    post change_planned_workout_path(source), params: { subtype: "recovery", duration_minutes: 60 }
    proposal = plan.adaptation_proposals.sole
    changed_attributes = source.reload.attributes.slice("kind", "subtype", "duration_minutes", "name", "estimated_if", "estimated_tss")

    post accept_adaptation_proposal_path(proposal)

    expect(response).to redirect_to(root_path)
    expect(source.reload.attributes.slice(*changed_attributes.keys)).to eq(changed_attributes)
    expect(PlannedWorkout).not_to exist(replaceable.id)
    expect(plan.planned_workouts.find_by!(scheduled_on: Date.current + 3).duration_minutes).to eq(75)
  end

  it "WKO-005 does not offer replanning for a non-material change" do
    allow(Workouts::Variations).to receive(:for_generation).with(:endurance).and_return("sustained")
    post change_planned_workout_path(workout), params: { subtype: "endurance", duration_minutes: 60 }

    expect(plan.adaptation_proposals).to be_empty
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

  it "WKO-007 copies a structured workout to an empty date" do
    destination = Date.current + 2
    workout

    expect do
      post copy_planned_workout_path(workout), params: { scheduled_on: destination.iso8601 }
    end.to change(PlannedWorkout, :count).by(1)

    expect(response).to redirect_to(root_path)
    copy = plan.planned_workouts.find_by!(scheduled_on: destination)
    expect(copy).to be_structured
    expect(copy.workout_steps.map(&:attributes)).not_to be_empty
    expect(workout.reload.scheduled_on).to eq(plan.starts_on + 1)
  end

  it "MIS-001 retains a past workout with a missed calendar status after resolution" do
    past = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 1)

    post miss_planned_workout_path(past), params: { resolution: "leave_unchanged" }

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(past.reload).to be_missed
    expect(response.body).to include("Missed")
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
