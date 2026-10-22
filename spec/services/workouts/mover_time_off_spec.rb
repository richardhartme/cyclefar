require "rails_helper"

# Pins how a Move reads the time-off timeline, so its recovery-week and
# return-ramp rules can be shared without changing behaviour.
RSpec.describe Workouts::Mover, "around time off", type: :service, generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, starts_on: today - 28, ends_on: today + 55, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let!(:base) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: today - 1) }
  let!(:build) { create(:plan_phase, training_plan: plan, starts_on: today, ends_on: today + 54, kind: :build, position: 2) }

  before { travel_to today }

  # A 14-day ramp after a break ending yesterday: stages 0-3 start on days 0, 4, 7 and 11.
  def create_break_after_reaching_level_three
    reached = generated_workout(plan: plan, phase: base, date: today - 10, duration: 120, level: 3)
    reached.update!(generation_context: { "generated_level" => 3, "generated_tss" => reached.estimated_tss })
    create(:time_off_period, training_plan: plan, starts_on: today - 6, ends_on: today - 1, reason: :illness, return_ramp_days: 14)
  end

  def moved_workout(to:)
    workout = generated_workout(plan: plan, phase: base, date: today - 7, duration: 120, level: 1)
    described_class.new(workout).move_to!(destination: to)
    workout.reload
  end

  context "after an illness break" do
    before { create_break_after_reaching_level_three }

    {
      "the first ramp day" => [ 0, 1 ],
      "the last day of stage 0" => [ 3, 1 ],
      "the first day of stage 1" => [ 4, 1 ],
      "the last day of stage 1" => [ 6, 1 ],
      "the first day of stage 2" => [ 7, 1 ],
      "the last day of stage 2" => [ 10, 1 ],
      "the first day of stage 3" => [ 11, 3 ],
      "the last ramp day" => [ 13, 3 ],
      "the first day after the ramp" => [ 14, 5 ]
    }.each do |description, (offset, ceiling)|
      it "bounds a move to #{description} at level #{ceiling}" do
        workout = moved_workout(to: today + offset)

        expect(workout.generation_context).to include("maximum_level" => ceiling)
        expect(workout.progression_level).to be <= ceiling
      end
    end

    it "regenerates a move that crosses a ramp stage and keeps one that stays inside a stage" do
      workout = generated_workout(plan: plan, phase: build, date: today + 5, duration: 60, level: 1)
      mover = described_class.new(workout)

      expect(mover.move_to!(destination: today + 6).regenerated).to be(false)
      expect(mover.move_to!(destination: today + 7).regenerated).to be(true)
    end

    it "regenerates a move out of the ramp into ordinary progression" do
      workout = generated_workout(plan: plan, phase: build, date: today + 13, duration: 60, level: 1)

      expect(described_class.new(workout).move_to!(destination: today + 14).regenerated).to be(true)
    end
  end

  context "with a hard/recovery cycle aligned to a phase transition" do
    let(:today) { Date.new(2026, 10, 5) }
    let(:plan) { create(:training_plan, starts_on: today, ends_on: today + 90, progression_mode: :hard_recovery_cycle, hard_weeks_before_recovery: 3) }
    let!(:base) { create(:plan_phase, training_plan: plan, starts_on: today, ends_on: today + 34) }
    let!(:build) { create(:plan_phase, training_plan: plan, starts_on: today + 35, ends_on: plan.ends_on, kind: :build, position: 2) }

    # Three hard weeks would put recovery in the week of day 21, but the build
    # transition on day 35 pulls it to the last full week before it, day 28.
    def move_from_day_fourteen_to(offset)
      workout = generated_workout(plan: plan, phase: base, date: today + 14, duration: 120, level: 3)
      described_class.new(workout).move_to!(destination: today + offset)
      workout.reload
    end

    it "caps a move into the aligned recovery week, the one the calendar shows" do
      expect(move_from_day_fourteen_to(28)).to have_attributes(progression_level: 1)
    end

    it "does not cap a move into the week where an unaligned cycle would have put recovery" do
      expect(move_from_day_fourteen_to(21).progression_level).to be > 1
    end
  end
end
