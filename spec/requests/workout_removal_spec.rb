require "rails_helper"

RSpec.describe "CYF-80 workout removal", type: :request do
  let(:user) { create(:user) }
  let(:plan) { create(:training_plan, user: user, starts_on: Date.current - 14, ends_on: Date.current + 70) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }

  before { sign_in_as(user) }

  [
    [ "past", -1, :planned, :structured, :workout ],
    [ "today", 0, :planned, :structured, :workout ],
    [ "future", 1, :planned, :structured, :workout ],
    [ "distant outline", 20, :planned, :outline, :workout ],
    [ "missed", -2, :missed, :structured, :workout ],
    [ "opener", 2, :planned, :structured, :opener ]
  ].each do |label, offset, status, detail, kind|
    it "WKO-010 offers confirmed removal for a #{label} workout and leaves the date empty on calendar refresh" do
      traits = detail == :structured ? [ :structured ] : []
      workout = create(
        :planned_workout,
        *traits,
        training_plan: plan,
        plan_phase: phase,
        scheduled_on: Date.current + offset,
        status: status,
        kind: kind,
        name: "Session to remove")
      template = create(:availability_template, training_plan: plan)
      create(:availability_slot, availability_template: template, weekday: workout.scheduled_on.cwday)

      get planned_workout_path(workout)

      form = Nokogiri::HTML(response.body).css("form").find do |candidate|
        candidate["action"] == planned_workout_path(workout) && candidate.at_css('input[name="_method"][value="delete"]')
      end
      expect(form).to be_present
      expect(form.text).to include("Remove workout")
      expect(form["data-turbo-confirm"]).to include("Remove this workout?")

      delete planned_workout_path(workout)

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(root_path)
      expect(PlannedWorkout).not_to exist(workout.id)
      expect(WorkoutStep.where(planned_workout_id: workout.id)).to be_empty
      2.times do
        get root_path
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Session to remove")
        expect(plan.planned_workouts.where(scheduled_on: workout.scheduled_on)).to be_empty
      end
    end
  end

  it "preserves completed snapshots, steps and feedback and offers no removal control" do
    workout = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase)
    history = [ workout.attributes, workout.workout_steps.map(&:attributes), workout.workout_feedback.attributes ]

    get planned_workout_path(workout)
    expect(response.body).not_to include("Remove workout")

    delete planned_workout_path(workout)

    expect(response).to redirect_to(planned_workout_path(workout))
    expect(flash[:alert]).to eq("Completed workouts cannot be removed")
    expect([ workout.reload.attributes, workout.workout_steps.reload.map(&:attributes), workout.workout_feedback.reload.attributes ]).to eq(history)
  end

  it "requires sign-in before removing a workout" do
    workout = create(:planned_workout, training_plan: plan, plan_phase: phase)
    delete session_path

    delete planned_workout_path(workout)

    expect(response).to redirect_to(new_session_path)
    expect(PlannedWorkout).to exist(workout.id)
  end
end
