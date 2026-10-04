require "rails_helper"

RSpec.describe "GEN-001 concurrent materialisation", type: :model do
  uses_transaction "structures an outline once across simultaneous requests"

  it "structures an outline once across simultaneous requests" do
    user = create(:user)
    plan = create(
      :training_plan,
      user: user,
      starts_on: Date.current,
      ends_on: Date.current + 83,
      progression_mode: :continuous,
      hard_weeks_before_recovery: nil,
      progression_state: { "intensity_bias" => -1 })
    phase = create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    workout = create(
      :planned_workout,
      training_plan: plan,
      plan_phase: phase,
      scheduled_on: Date.current,
      intent: :threshold,
      subtype: :threshold,
      progression_level: 3,
      duration_minutes: 90,
      variation_key: "standard")
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          own_plan_instance = TrainingPlan.find(plan.id)
          ready << true
          start.pop
          Planning::WorkoutBuilder.new(own_plan_instance).call
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:value)
    definition = Workouts::Generator.new(subtype: :threshold, duration_minutes: 90, progression_level: 2, variation_key: "standard").call
    expect(workout.reload.progression_level).to eq(2)
    expect(workout.workout_steps.count).to eq(definition.steps.length)
    expect(workout.workout_steps.sum(:duration_seconds)).to eq(90 * 60)
  ensure
    threads&.each(&:join)
    plan&.destroy!
    user&.destroy!
  end
end
