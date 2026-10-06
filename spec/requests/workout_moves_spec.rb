require "rails_helper"

RSpec.describe "WKO-006 / MIS-001 destination-aware moves", type: :request, generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:user) { create(:user) }
  let(:plan) { create(:training_plan, user: user, starts_on: today - 28, ends_on: today + 55, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let!(:base) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: today - 1) }
  let!(:build) { create(:plan_phase, training_plan: plan, kind: :build, starts_on: today, ends_on: plan.ends_on, position: 2) }

  before do
    travel_to today
    sign_in_as(user)
  end

  [ :ordinary, :missed ].each do |path|
    context "#{path} move" do
      def post_move(workout, destination, path)
        if path == :ordinary
          post move_planned_workout_path(workout), params: { scheduled_on: destination.iso8601 }
        else
          post miss_planned_workout_path(workout), params: { resolution: "move", scheduled_on: destination.iso8601 }
        end
      end

      it "regenerates a phase-boundary move, displays updated workout detail and preserves completed history" do
        workout = generated_workout(plan: plan, phase: base, date: today - 1, duration: 120, level: 1)
        completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: build, scheduled_on: today + 1)
        history = [ completed.attributes, completed.workout_steps.map(&:attributes), completed.workout_feedback.attributes ]

        post_move(workout, today + 2, path)

        expect(response).to redirect_to(root_path)
        expect(workout.reload).to have_attributes(plan_phase: build, progression_level: 3, subtype: "threshold", duration_minutes: 120, status: "planned")
        get planned_workout_path(workout)
        expect(response.body).to include("Build phase", workout.name, (today + 2).to_fs(:long))
        expect([ completed.reload.attributes, completed.workout_steps.map(&:attributes), completed.workout_feedback.attributes ]).to eq(history)
      end

      it "shows destination load warnings outside the 14-day horizon on subsequent calendar requests" do
        generated_workout(plan: plan, phase: build, date: today, duration: 60, subtype: :endurance)
        workout = generated_workout(plan: plan, phase: base, date: today - 1, duration: 120, level: 1)
        destination = today + 30

        post_move(workout, destination, path)

        expect(response).to redirect_to(root_path)
        expect(workout.reload.progression_level).to eq(1)
        follow_redirect!
        expect(response.body).to include("above the load growth target")
        expect(response.body).to include(new_availability_change_path(effective_from: destination.beginning_of_week.iso8601).gsub("&", "&amp;"))
        get root_path
        expect(response.body).to include("above the load growth target", destination.beginning_of_week.to_fs(:long))
      end

      it "does not disclose or mutate another rider's workout on a regeneration request" do
        foreign_plan = create(:training_plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
        phase = create(:plan_phase, training_plan: foreign_plan, ends_on: foreign_plan.ends_on)
        workout = generated_workout(plan: foreign_plan, phase: phase, date: today - 1)
        original = [ workout.attributes, workout.workout_steps.map(&:attributes) ]

        post_move(workout, today + 30, path)

        expect(response).to have_http_status(:not_found)
        body = response.body
        post_move(0, today + 30, path)
        expect(response).to have_http_status(:not_found)
        expect(response.body).to eq(body)
        expect([ workout.reload.attributes, workout.workout_steps.map(&:attributes) ]).to eq(original)
      end
    end
  end
end
