require "rails_helper"

RSpec.describe "OFF-001 return prescriptions", generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, starts_on: today - 56, ends_on: today + 70, include_base: false, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on, kind: :build) }
  let(:slots) { (1..7).map { |day| { weekday: day, duration_minutes: 90, intent: "threshold" } } }
  let(:period) { create(:time_off_period, training_plan: plan, starts_on: today - 3, ends_on: today - 1, reason: :illness, return_ramp_days: 16) }
  let(:prescriber) { Planning::FuturePrescriber.new(plan: plan, slots: slots) }

  before do
    travel_to today
    phase
  end

  def prior(date:, subtype: :threshold, level: 4, status: :planned)
    workout = generated_workout(plan: plan, phase: phase, date: date, subtype: subtype, level: level, duration: 120)
    workout.update!(status: status) if status == :missed
    workout
  end

  %w[sustained alternating undulating].each do |profile|
    it "keeps all four stages bounded through initial #{profile} selection and later materialisation" do
      prior(date: today - 7)
      period
      plan.update!(progression_state: { "intensity_bias" => 2 })
      allow(Workouts::Variations).to receive(:for_generation).and_call_original
      allow(Workouts::Variations).to receive(:for_generation).with("endurance", current_key: "sustained").and_return(profile)
      prescriber.replace!(today..plan.ends_on)
      stage_examples = [ 0, 4, 8, 12 ].map { |offset| plan.planned_workouts.find_by!(scheduled_on: today + offset) }
      expect(stage_examples.map(&:subtype)).to eq(%w[recovery endurance tempo threshold])
      expect(stage_examples.map(&:duration_minutes)).to eq([ 54, 63, 72, 90 ])
      expect(stage_examples.map { |workout| workout.generation_context["return_ramp_stage"] }).to eq([ 1, 2, 3, 4 ])
      stage_examples.first(3).zip([ [ 45, 60 ], [ 55, 68 ], [ 78, 87 ] ]).each do |workout, band|
        workout.workout_steps.each do |step|
          targets = [ step.target_low_pct_ftp, step.target_high_pct_ftp, step.end_target_low_pct_ftp, step.end_target_high_pct_ftp ].compact
          expect(targets).to all(be <= band.last)
          expect(targets).to all(be >= band.first) if step.group_key == "main"
        end
        expect(workout.workout_steps.sum(:duration_seconds)).to eq(workout.duration_minutes * 60)
        expected = Metrics::WorkoutCalculator.new(steps: workout.workout_steps, ftp_watts: plan.initial_ftp_watts).call
        expect(workout.estimated_tss).to be_within(0.001).of(expected.estimated_tss)
      end
      expect(stage_examples[1].variation_key).to eq(profile)
      expect(stage_examples[2].progression_level).to eq(1)
      expect(stage_examples[3].progression_level).to eq(3)
      expect(stage_examples[0].purpose).to include("Return-to-training stage 1")
      later = plan.planned_workouts.find_by!(scheduled_on: today + 15)
      expect(later).to be_outline
      expect(later.generation_context["maximum_level"]).to eq(3)
      snapshot = stage_examples[1].workout_steps.map(&:attributes)
      Planning::WorkoutBuilder.new(plan, date: today + 14).call
      expect(later.reload).to have_attributes(detail_status: "structured", progression_level: 3)
      expect(stage_examples[1].reload.workout_steps.map(&:attributes)).to eq(snapshot)
      expect(period.reload.return_ramp_days).to eq(16)
      expect(plan.reload.ends_on).to eq(today + 70)
    end
  end

  it "uses the latest comparable session rather than old high levels, another family or missed training" do
    prior(date: today - 35, level: 7)
    prior(date: today - 7, subtype: :sweet_spot, level: 4)
    prior(date: today - 6, subtype: :vo2_max, level: 7)
    prior(date: today - 5, level: 6, status: :missed)
    period
    prescriber.replace!(today..today + 30)
    returned = plan.planned_workouts.find_by!(scheduled_on: today + 12)
    expect(returned.progression_level).to eq(3)
    expect(plan.planned_workouts.find_by!(scheduled_on: today + 16).generation_context["maximum_level"]).to eq(3)
    expect(plan.planned_workouts.find_by!(scheduled_on: today + 23).generation_context["maximum_level"]).to eq(4)
  end

  it "falls back to level one when there is no comparable pre-break training" do
    prior(date: today - 7, subtype: :vo2_max, level: 7)
    period
    prescriber.replace!(today..today + 13)
    expect(plan.planned_workouts.find_by!(scheduled_on: today + 12).progression_level).to eq(1)
  end

  [ 2, 3 ].each do |days|
    it "collapses a #{days}-day ramp and preserves completed workouts and steps" do
      prior(date: today - 7)
      period.update!(reason: :recovery, return_ramp_days: days)
      completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: today + 6)
      snapshot = [ completed.attributes, completed.workout_steps.map(&:attributes), completed.workout_feedback.attributes ]
      prescriber.replace!(today..plan.ends_on)
      stages = plan.planned_workouts.planned.where(scheduled_on: today..today + days - 1).order(:scheduled_on)
      expect(stages.map { |workout| workout.generation_context["return_ramp_stage"] }).to eq(days == 2 ? [ 1, 3 ] : [ 1, 2, 3 ])
      expect(plan.planned_workouts.group(:scheduled_on).count.values).to all(eq(1))
      expect([ completed.reload.attributes, completed.workout_steps.map(&:attributes), completed.workout_feedback.reload.attributes ]).to eq(snapshot)
      expect(period.reload.return_ramp_days).to eq(days)
      expect(plan.reload.ends_on).to eq(today + 70)
    end
  end

  it "uses comparable levels for holiday resumption without applying an illness reduction" do
    prior(date: today - 35, level: 7)
    prior(date: today - 7, level: 3)
    period.update!(reason: :holiday, return_ramp_days: nil)
    plan.update!(progression_state: { "intensity_bias" => 2 })
    prescriber.replace!(today..today + 13)
    returned = plan.planned_workouts.find_by!(scheduled_on: today)
    # The actual weekly cap can reduce a dense daily schedule further.
    expect(returned.generation_context["maximum_level"]).to eq(3)
    expect(returned.progression_level).to be <= 3
    expect(returned.generation_context["return_ramp_stage"]).to be_nil
  end

  it "saves an easy outline's power limits outside the horizon before sampling its initial profile" do
    period.update!(return_ramp_days: 40)
    easy = (1..7).map { |day| { weekday: day, duration_minutes: 90, intent: "endurance" } }
    Planning::FuturePrescriber.new(plan: plan, slots: easy).replace!(today..plan.ends_on)
    later = plan.planned_workouts.find_by!(scheduled_on: today + 18)
    expect(later).to be_outline
    expect(later.generation_context.fetch("load_adjustments")).to include("return_target_band" => [ 55, 68 ])
    allow(Workouts::Variations).to receive(:for_generation).with("endurance", current_key: "sustained").and_return("undulating")
    Planning::WorkoutBuilder.new(plan, date: later.scheduled_on).call
    expect(later.reload).to have_attributes(detail_status: "structured", variation_key: "undulating", duration_minutes: 63)
    expect(later.workout_steps.map(&:target_high_pct_ftp)).to all(be <= 68)
    expect(later.workout_steps.map(&:end_target_high_pct_ftp).compact).to all(be <= 68)
    expect(later.purpose).to include("Return-to-training stage 2")
  end

  it "retains the 30-minute minimum across every stage" do
    period
    short = (1..7).map { |day| { weekday: day, duration_minutes: 30, intent: "threshold" } }
    Planning::FuturePrescriber.new(plan: plan, slots: short).replace!(today..today + 15)
    expect(plan.planned_workouts.where(scheduled_on: today..today + 15).pluck(:duration_minutes)).to all(eq(30))
  end
end
