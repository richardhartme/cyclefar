require "rails_helper"

RSpec.describe "CYF-8 destination errors", type: :request, generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:user) { create(:user) }
  let(:plan) { create(:training_plan, :event, user: user, starts_on: today - 7, ends_on: today + 35) }
  let!(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let!(:workout) { generated_workout(plan: plan, phase: phase, date: today - 1, variation: :standard) }

  before do
    travel_to today
    sign_in_as(user)
  end

  [ :add, :copy, :move, :missed_move ].each do |action|
    context action.to_s do
      define_method(:submit_destination) do |date|
        params = { scheduled_on: date.iso8601 }
        case action
        when :add
          post planned_workouts_path, params: params.merge(subtype: "threshold", duration_minutes: 60)
        when :copy
          post copy_planned_workout_path(workout), params: params
        when :move
          post move_planned_workout_path(workout), params: params
        when :missed_move
          post miss_planned_workout_path(workout), params: params.merge(resolution: "move")
        end
      end

      [ :time_off, :target_event ].each do |blocked|
        it "shows a useful #{blocked} error and leaves the source unchanged" do
          if blocked == :time_off
            destination = today + 3
            create(:time_off_period, training_plan: plan, starts_on: destination, ends_on: destination)
            message = "Workouts cannot be scheduled during time off"
          else
            destination = plan.ends_on
            create(:target_event, training_plan: plan)
            message = "Workouts cannot be scheduled on the target event date"
          end
          original = [ workout.attributes, workout.workout_steps.map(&:attributes) ]

          expect { submit_destination(destination) }.not_to change(PlannedWorkout, :count)

          expect(response).to redirect_to(action == :add ? root_path : planned_workout_path(workout))
          follow_redirect!
          expect(response.body).to include(message)
          expect([ workout.reload.attributes, workout.workout_steps.reload.map(&:attributes) ]).to eq(original)
          expect(plan.planned_workouts.exists?(scheduled_on: destination)).to be(false)
        end
      end

      it "accepts an empty date and returns to the calendar" do
        submit_destination(today + 2)
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response).to have_http_status(:ok)
        expect(plan.planned_workouts.find_by!(scheduled_on: today + 2)).to be_planned
      end
    end
  end
end
