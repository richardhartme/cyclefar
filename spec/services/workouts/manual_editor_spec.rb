require "rails_helper"

RSpec.describe Workouts::ManualEditor, type: :service do
  let(:plan) { create(:training_plan) }
  let(:phase) { create(:plan_phase, training_plan: plan, ends_on: plan.ends_on) }
  let(:workout) { create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, subtype: :threshold, intent: :threshold, progression_level: 3, variation_key: "a", scheduled_on: plan.starts_on + 1) }

  before do
    definition = Workouts::Generator.new(subtype: :threshold, duration_minutes: 60, progression_level: 3, phase: :base, goal: :increase_ftp, discipline: :road, variation_key: "a").call
    metrics = Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: plan.initial_ftp_watts).call
    workout.workout_steps.destroy_all
    workout.assign_attributes(name: definition.name, purpose: definition.purpose, estimated_np_watts: metrics.estimated_np_watts, estimated_if: metrics.estimated_if, estimated_tss: metrics.estimated_tss, estimated_work_kj: metrics.estimated_work_kj)
    definition.steps.each { |step| workout.workout_steps.build(step.to_h) }
    workout.save!
  end

  it "WKO-004 shuffles Same deterministically while preserving subtype, duration and approximate load" do
    before = workout.estimated_tss
    described_class.new(workout).apply!(action: :same)
    expect(workout.reload).to have_attributes(subtype: "threshold", duration_minutes: 60, variation_key: "b")
    expect((workout.estimated_tss / before - 1).abs).to be <= 0.05
    expect(workout.workout_steps.sum(:duration_seconds)).to eq(3600)
  end

  it "WKO-004 adjusts only the selected workout's level for easier and harder" do
    described_class.new(workout).apply!(action: :harder)
    expect(workout.reload.progression_level).to eq(4)
    described_class.new(workout).apply!(action: :easier)
    expect(workout.reload.progression_level).to eq(3)
    expect(plan.reload.progression_state).to eq({})
  end

  it "WKO-004 enforces the 30 minute minimum and regenerates exact 15 minute changes" do
    described_class.new(workout).apply!(action: :shorter)
    expect(workout.reload.duration_minutes).to eq(45)
    described_class.new(workout).apply!(action: :shorter)
    expect(workout.reload.duration_minutes).to eq(30)
    expect { described_class.new(workout).apply!(action: :shorter) }.to raise_error(ArgumentError, /below 30/)
    described_class.new(workout).apply!(action: :longer)
    expect(workout.reload.duration_minutes).to eq(45)
  end

  it "WKO-005 changes subtype and exposes material changes without a replan" do
    result = described_class.new(workout).apply!(action: :change, subtype: :recovery, duration_minutes: 60)
    expect(result.material_change).to be(true)
    expect(workout.reload.subtype).to eq("recovery")
    expect(plan.planned_workouts.where.not(id: workout.id).count).to eq(0)
  end
end
