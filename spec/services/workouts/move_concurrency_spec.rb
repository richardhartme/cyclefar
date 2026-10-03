require "rails_helper"

RSpec.describe "CYF-7 concurrent workout moves", type: :model, generated_workouts: true do
  uses_transaction "allows only one of two simultaneous moves onto the same date"

  it "allows only one of two simultaneous moves onto the same date" do
    user = create(:user)
    plan = create(:training_plan, user: user, starts_on: Date.current, ends_on: Date.current + 69, progression_mode: :continuous, hard_weeks_before_recovery: nil)
    phase = create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    workouts = [ 1, 2 ].map { |offset| generated_workout(plan: plan, phase: phase, date: Date.current + offset) }
    destination = Date.current + 20
    ready = Queue.new
    start = Queue.new
    threads = workouts.map do |workout|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          mover = Workouts::Mover.new(PlannedWorkout.find(workout.id))
          ready << true
          start.pop
          begin
            mover.move_to!(destination: destination)
            :moved
          rescue ArgumentError => error
            raise unless error.message.include?("already has a workout")

            :occupied
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    expect(threads.map(&:value)).to contain_exactly(:moved, :occupied)
    expect(plan.planned_workouts.where(scheduled_on: destination).count).to eq(1)
    expect(plan.planned_workouts.count).to eq(2)
    plan.planned_workouts.each do |workout|
      expect(workout.workout_steps.sum(:duration_seconds)).to eq(workout.duration_minutes * 60)
    end
  ensure
    threads&.each(&:join)
    plan&.reload&.destroy!
    user&.destroy!
  end
end
