require "rails_helper"

RSpec.describe "CYF-8 workout destinations", type: :service, generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, :event, starts_on: today - 7, ends_on: today + 35, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let!(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let!(:workout) { generated_workout(plan: plan, phase: phase, date: today - 1, variation: :standard) }
  let!(:completed) { create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: today - 2) }

  before { travel_to today }

  def snapshot
    [ PlannedWorkout, WorkoutStep, WorkoutFeedback ].map { |model| model.order(:id).map(&:attributes) }
  end

  [ :add, :copy, :move, :missed_move ].each do |action|
    context action.to_s do
      define_method(:place_workout) do |destination|
        case action
        when :add
          Workouts::Creator.new(plan).create!(scheduled_on: destination, subtype: :threshold, duration_minutes: 60)
        when :copy
          Workouts::Copier.new(workout).copy_to!(destination: destination)
        when :move
          Workouts::Mover.new(workout).move_to!(destination: destination).workout
        when :missed_move
          Planning::MissedWorkoutResolver.new(workout).resolve!(mode: :move, destination: destination.iso8601).workout
        end
      end

      def expect_rejection(destination, message)
        original = snapshot
        expect { place_workout(destination) }.to raise_error(ArgumentError, message)
        expect(snapshot).to eq(original)
      end

      %w[holiday illness recovery event other].each do |reason|
        it "OFF-001 rejects the first, middle and last dates of #{reason} without altering workouts, steps or feedback" do
          create(
            :time_off_period,
            training_plan: plan,
            starts_on: today + 3,
            ends_on: today + 5,
            reason: reason,
            return_ramp_days: %w[illness recovery].include?(reason) ? 7 : nil)

          (today + 3..today + 5).each { |date| expect_rejection(date, /during time off/) }
        end
      end

      it "rejects a single-day time off" do
        create(:time_off_period, training_plan: plan, starts_on: today + 3, ends_on: today + 3)
        expect_rejection(today + 3, /during time off/)
      end

      it "PLN-022 rejects an empty target-event date" do
        create(:target_event, training_plan: plan)
        expect_rejection(plan.ends_on, /target event date/)
      end

      it "rejects dates immediately outside either plan boundary" do
        [ plan.starts_on - 1, plan.ends_on + 1 ].each { |date| expect_rejection(date, /inside this plan/) }
      end

      it "rejects occupied dates, including completed history" do
        expect_rejection(completed.scheduled_on, /already has a workout/)
      end

      it "#{%i[move missed_move].include?(action) ? 'allows a same-date move' : 'requires a date other than the source'}" do
        if %i[move missed_move].include?(action)
          original_steps = workout.workout_steps.map(&:attributes)
          expect(place_workout(workout.scheduled_on)).to eq(workout)
          expect(workout.workout_steps.reload.map(&:attributes)).to eq(original_steps)
        else
          expect_rejection(workout.scheduled_on, /already has a workout/)
        end
      end

      it "rejects an in-plan date without a phase" do
        phase.update!(ends_on: plan.ends_on - 1)
        expect_rejection(plan.ends_on, /covered by a plan phase/)
      end

      [ :starts_on, :ends_on ].each do |boundary|
        it "accepts an empty #{boundary} date and preserves completed history" do
          history = [ completed.attributes, completed.workout_steps.map(&:attributes), completed.workout_feedback.attributes ]
          result = place_workout(plan.public_send(boundary))
          expect(result).to have_attributes(scheduled_on: plan.public_send(boundary), status: "planned", detail_status: "structured")
          expect([ completed.reload.attributes, completed.workout_steps.reload.map(&:attributes), completed.workout_feedback.reload.attributes ]).to eq(history)
        end
      end

      [ 2, 6 ].each do |offset|
        it "allows an empty date #{offset == 2 ? 'before' : 'after'} time off" do
          create(:time_off_period, training_plan: plan, starts_on: today + 3, ends_on: today + 5)
          result = place_workout(today + offset)
          expect(result.scheduled_on).to eq(today + offset)
        end
      end

      it "ignores another rider's time off and target event" do
        other_plan = create(:training_plan, :event, starts_on: today - 7, ends_on: today + 3)
        create(:target_event, training_plan: other_plan)
        create(:time_off_period, training_plan: other_plan, starts_on: today + 3, ends_on: today + 3)
        expect(place_workout(today + 3).scheduled_on).to eq(today + 3)
      end
    end
  end
end
