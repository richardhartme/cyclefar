require "rails_helper"

RSpec.describe Workouts::Mover, type: :service, generated_workouts: true do
  let(:today) { Date.new(2026, 10, 5) }
  let(:plan) { create(:training_plan, starts_on: today - 28, ends_on: today + 55, progression_mode: :continuous, hard_weeks_before_recovery: nil) }
  let!(:base) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: today - 1) }
  let!(:build) { create(:plan_phase, training_plan: plan, starts_on: today, ends_on: today + 34, kind: :build, position: 2) }
  let!(:speciality) { create(:plan_phase, training_plan: plan, starts_on: today + 35, ends_on: plan.ends_on, kind: :speciality, position: 3) }

  before { travel_to today }

  def steps(workout)
    workout.workout_steps.reload.map(&:attributes)
  end

  shared_examples "destination-aware moves" do
    def move(workout, date)
      if self.class.metadata[:move_path] == :missed
        Planning::MissedWorkoutResolver.new(workout).resolve!(mode: :move, destination: date.iso8601)
      else
        described_class.new(workout).move_to!(destination: date)
      end
    end

    it "WKO-006/MIS-001 preserves exact steps, variation and manual levels for a seven-day same-phase move" do
      workout = generated_workout(plan: plan, phase: build, date: today + 1, level: 6, duration: 120, variation: "redistributed_recovery")
      workout.update!(generation_context: { "baseline_level" => 3, "generated_level" => 3, "generated_tss" => 100 })
      original = steps(workout)
      context = workout.generation_context

      result = move(workout, today + 8)

      expect(result.regenerated).to be(false)
      expect(workout.reload).to have_attributes(scheduled_on: today + 8, plan_phase: build, progression_level: 6, status: "planned", variation_key: "redistributed_recovery")
      expect(steps(workout)).to eq(original)
      expect(workout.generation_context).to eq(context)
    end

    it "regenerates a five-day phase-boundary move at destination progression, preserving subtype, intent and duration" do
      workout = generated_workout(plan: plan, phase: base, date: today - 5, level: 4, duration: 120)
      workout.update!(intent: :intervals, generation_context: { "baseline_level" => 4, "maximum_level" => 1 })
      original = steps(workout)

      result = move(workout, today)

      expect(result.regenerated).to be(true)
      expect(workout.reload).to have_attributes(plan_phase: build, progression_level: 3, subtype: "threshold", intent: "intervals", duration_minutes: 120, status: "planned")
      expect(workout.generation_context).to include("baseline_level" => 3, "generated_level" => 3)
      expect(workout.generation_context).not_to have_key("maximum_level")
      expect(steps(workout)).not_to eq(original)
      expect(workout.workout_steps.sum(:duration_seconds)).to eq(7200)
      expect(workout.purpose).to include("Build phase")
    end

    [ [ 1, 17, 5 ], [ 24, 4, 3 ] ].each do |source, destination, level|
      it "regenerates a long #{destination > source ? 'forward' : 'backward'} same-phase move using its destination date" do
        workout = generated_workout(plan: plan, phase: build, date: today + source, level: 1, duration: 120)
        move(workout, today + destination)
        expect(workout.reload.progression_level).to eq(level)
        expect(workout.generation_context.fetch("baseline_level")).to eq(level)
      end
    end

    it "uses the owner's accepted bias and FTP while leaving another rider and completed history unchanged" do
      plan.update!(progression_state: { "intensity_bias" => 1 })
      create(:rider_profile, user: plan.user, ftp_watts: 300)
      other_plan = create(:training_plan, starts_on: plan.starts_on, ends_on: plan.ends_on, progression_state: { "intensity_bias" => -2 })
      create(:rider_profile, user: other_plan.user, ftp_watts: 400)
      other = create(:planned_workout, :completed, training_plan: other_plan, scheduled_on: today + 17)
      completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: base, scheduled_on: today - 7)
      generated_workout(plan: plan, phase: base, date: today - 6, level: 1, duration: 300)
      history = [ completed.attributes, steps(completed), other.attributes, steps(other) ]
      workout = generated_workout(plan: plan, phase: build, date: today + 1, level: 1, duration: 120)

      Current.set(session: other_plan.user.sessions.create!) { move(workout, today + 17) }

      expect(workout.reload.progression_level).to eq(6)
      expected = Metrics::WorkoutCalculator.new(steps: workout.workout_steps, ftp_watts: 300).call
      expect(workout.estimated_work_kj.to_f).to be_within(0.01).of(expected.estimated_work_kj)
      expect([ completed.reload.attributes, steps(completed), other.reload.attributes, steps(other) ]).to eq(history)
      expect(plan.reload.progression_state).to eq("intensity_bias" => 1)
    end

    it "rejects collisions with planned, missed and completed records without rewriting the source" do
      workout = generated_workout(plan: plan, phase: build, date: today + 1)
      original = [ workout.attributes, steps(workout) ]
      [ :planned, :missed, :completed ].each_with_index do |status, index|
        destination = today + index + 3
        occupied = create(:planned_workout, status == :completed ? :completed : :structured, training_plan: plan, plan_phase: build, scheduled_on: destination)
        occupied.update!(status: status) unless status == :completed
        expect { move(workout, destination) }.to raise_error(ArgumentError, /already has a workout/)
        expect([ workout.reload.attributes, steps(workout) ]).to eq(original)
      end
    end

    it "rejects completed or concurrently completed sources" do
      workout = generated_workout(plan: plan, phase: build, date: today + 1)
      stale = PlannedWorkout.find(workout.id)
      Adaptations::CompletionRecorder.new(workout: workout, rpe: 8, completion_quality: :as_planned).call
      original = [ workout.reload.attributes, steps(workout) ]
      expect { move(stale, today + 17) }.to raise_error(ArgumentError)
      expect([ workout.reload.attributes, steps(workout) ]).to eq(original)
    end

    it "rolls back the date, phase, deleted steps and metrics when regenerated persistence fails" do
      workout = generated_workout(plan: plan, phase: base, date: today - 1, level: 4, duration: 120)
      original = [ workout.attributes, steps(workout) ]
      allow(workout).to receive(:save!).and_wrap_original do |original, *args, **kwargs|
        raise ActiveRecord::RecordInvalid if workout.workout_steps.any?(&:new_record?)

        original.call(*args, **kwargs)
      end
      expect { move(workout, today + 17) }.to raise_error(ActiveRecord::RecordInvalid)
      expect([ workout.reload.attributes, steps(workout) ]).to eq(original)
    end
  end

  context "ordinary Move", move_path: :ordinary do
    include_examples "destination-aware moves"
  end

  context "missed-workout Move", move_path: :missed do
    include_examples "destination-aware moves"
  end

  it "keeps distant moved outlines as forecasts, then materialises without stacking bias" do
    plan.update!(progression_state: { "intensity_bias" => 1 })
    workout = create(:planned_workout, training_plan: plan, plan_phase: base, scheduled_on: today - 7, subtype: :threshold, intent: :threshold, duration_minutes: 120, progression_level: 1)
    described_class.new(workout).move_to!(destination: today + 17)
    expect(workout.reload).to be_outline
    expect(workout.workout_steps).to be_empty
    expect(workout.progression_level).to eq(6)
    forecast = workout.estimated_tss
    Planning::WorkoutBuilder.new(plan, date: today + 17).call
    expect(workout.reload).to be_structured
    expect(workout.progression_level).to eq(6)
    expect(workout.estimated_tss).to eq(forecast)
  end

  it "materialises an outline moved into the horizon without changing unrelated outlines" do
    workout = create(:planned_workout, training_plan: plan, plan_phase: build, scheduled_on: today + 8, subtype: :threshold, intent: :threshold, progression_level: 3)
    other = create(:planned_workout, training_plan: plan, plan_phase: build, scheduled_on: today + 2)
    original = other.attributes
    described_class.new(workout).move_to!(destination: today + 1)
    expect(workout.reload).to be_structured
    expect(other.reload.attributes).to eq(original)
  end

  it "keeps an opener executable across phases" do
    opener = Workouts::Creator.new(plan).create!(scheduled_on: today - 1, subtype: :opener, duration_minutes: 45)
    described_class.new(opener).move_to!(destination: today + 1)
    expect(opener.reload).to have_attributes(kind: "opener", duration_minutes: 45, name: "Event Opener", detail_status: "structured")
    expect(opener.workout_steps.sum(:duration_seconds)).to eq(2700)
  end

  it "rejects dates outside the plan, time off, the event date and missing phases" do
    workout = generated_workout(plan: plan, phase: build, date: today + 1)
    create(:time_off_period, training_plan: plan, starts_on: today + 3, ends_on: today + 4)
    [ plan.starts_on - 1, plan.ends_on + 1, today + 3 ].each do |date|
      expect { described_class.new(workout).move_to!(destination: date) }.to raise_error(ArgumentError)
      expect(workout.reload.scheduled_on).to eq(today + 1)
    end
    speciality.destroy!
    expect { described_class.new(workout).move_to!(destination: today + 36) }.to raise_error(ArgumentError, /plan phase/)
  end

  it "rejects the target event date and archived plans" do
    event_plan = create(:training_plan, :event, starts_on: plan.starts_on, ends_on: plan.ends_on)
    phase = create(:plan_phase, training_plan: event_plan, ends_on: event_plan.ends_on)
    create(:target_event, training_plan: event_plan)
    workout = generated_workout(plan: event_plan, phase: phase, date: today)
    expect { described_class.new(workout).move_to!(destination: event_plan.ends_on) }.to raise_error(ArgumentError, /target event date/)
    event_plan.update!(status: :archived)
    expect { described_class.new(workout).move_to!(destination: today + 1) }.to raise_error(ArgumentError, /active plan/)
    expect(workout.reload.scheduled_on).to eq(today)
  end

  it "regenerates at exactly eight days and retains an explicit endurance profile" do
    workout = generated_workout(plan: plan, phase: build, date: today + 1, subtype: :endurance, variation: "undulating")
    result = described_class.new(workout).move_to!(destination: today + 9)
    expect(result.regenerated).to be(true)
    expect(workout.reload).to have_attributes(subtype: "endurance", duration_minutes: 60, variation_key: "undulating", progression_level: nil)
    expect(workout.workout_steps.where(kind: :ramp).count).to be > 2
  end

  it "refreshes preserved-step metrics using current owner FTP when moving an overdue workout" do
    profile = create(:rider_profile, user: plan.user)
    workout = generated_workout(plan: plan, phase: build, date: today, level: 4)
    original = steps(workout)
    profile.update!(ftp_watts: 300)
    described_class.new(workout).move_to!(destination: today + 1)
    expect(steps(workout)).to eq(original)
    metrics = Metrics::WorkoutCalculator.new(steps: workout.workout_steps, ftp_watts: 300).call
    expect(workout.reload.estimated_work_kj.to_f).to be_within(0.01).of(metrics.estimated_work_kj)
  end

  it "preserves a short manual move even above the destination cap, returning a warning without changing other workouts" do
    reference = generated_workout(plan: plan, phase: build, date: today, duration: 120, subtype: :endurance)
    workout = generated_workout(plan: plan, phase: build, date: today + 6, duration: 120, level: 6)
    original = steps(workout)
    reference_before = reference.attributes
    result = described_class.new(workout).move_to!(destination: today + 8)
    expect(result.regenerated).to be(false)
    expect(result.warnings).to eq([ Planning::WeeklyLoadCap.warning((today + 8).beginning_of_week) ])
    expect(steps(workout)).to eq(original)
    expect(reference.reload.attributes).to eq(reference_before)
  end

  it "reduces only the regenerated session to fit the comparable-week cap when feasible" do
    reference = generated_workout(plan: plan, phase: build, date: today, duration: 135, subtype: :endurance)
    workout = generated_workout(plan: plan, phase: base, date: today - 1, duration: 120, level: 1)
    before = reference.attributes
    result = described_class.new(workout).move_to!(destination: today + 30)
    expect(workout.reload.progression_level).to be < 6
    expect(workout.estimated_tss.to_f).to be <= Planning::WeeklyLoadCap.limit(reference.estimated_tss.to_f)
    expect(result.warnings).to be_empty
    expect(reference.reload.attributes).to eq(before)
  end

  it "uses forecast load and keeps an impossible cap non-blocking at the lowest level" do
    generated_workout(plan: plan, phase: build, date: today, duration: 60, subtype: :endurance)
    fixed = create(:planned_workout, training_plan: plan, plan_phase: build, scheduled_on: today + 29, subtype: :endurance, duration_minutes: 180, estimated_tss: nil)
    workout = generated_workout(plan: plan, phase: base, date: today - 1, duration: 120, level: 1)
    before = fixed.attributes
    result = described_class.new(workout).move_to!(destination: today + 30)
    expect(workout.reload.progression_level).to eq(1)
    expect(result.warnings).to include(a_string_including("8% growth target"))
    expect(fixed.reload.attributes).to eq(before)
    expect(fixed.workout_steps).to be_empty
  end

  it "caps short moves into recovery weeks while preserving the requested subtype and duration" do
    cycle_plan = create(:training_plan, starts_on: today, ends_on: today + 55, progression_state: { "intensity_bias" => 2 })
    phase = create(:plan_phase, training_plan: cycle_plan, starts_on: today, ends_on: cycle_plan.ends_on, kind: :build)
    workout = generated_workout(plan: cycle_plan, phase: phase, date: today + 20, duration: 120, level: 6)
    result = described_class.new(workout).move_to!(destination: today + 21)
    expect(result.regenerated).to be(true)
    expect(workout.reload).to have_attributes(subtype: "threshold", duration_minutes: 120, progression_level: 1)
    expect(workout.generation_context).to include("maximum_level" => 1)
  end

  it "uses a taper ceiling rather than the source level or ceiling" do
    taper_plan = create(:training_plan, :event, starts_on: today - 28, ends_on: today + 6, progression_mode: :continuous, hard_weeks_before_recovery: nil, progression_state: { "intensity_bias" => 2 })
    phase = create(:plan_phase, training_plan: taper_plan, starts_on: taper_plan.starts_on, ends_on: today - 1, kind: :speciality)
    taper = create(:plan_phase, training_plan: taper_plan, starts_on: today, ends_on: today + 6, kind: :taper, position: 2)
    workout = generated_workout(plan: taper_plan, phase: phase, date: today - 1, duration: 120, level: 7)
    described_class.new(workout).move_to!(destination: today + 4)
    expect(workout.reload).to have_attributes(plan_phase: taper, progression_level: 2, subtype: "threshold", duration_minutes: 120)
  end

  it "bounds a return-ramp move by the reached pre-break level without changing subtype, duration or bias" do
    plan.update!(progression_state: { "intensity_bias" => 2 })
    reached = generated_workout(plan: plan, phase: base, date: today - 10, duration: 120, level: 3)
    reached.update!(generation_context: { "generated_level" => 3, "generated_tss" => reached.estimated_tss })
    create(:time_off_period, training_plan: plan, starts_on: today - 6, ends_on: today - 1, reason: :illness, return_ramp_days: 14)
    workout = generated_workout(plan: plan, phase: base, date: today - 7, duration: 120, level: 1)
    described_class.new(workout).move_to!(destination: today + 11)
    expect(workout.reload).to have_attributes(subtype: "threshold", duration_minutes: 120, progression_level: 3)
    expect(workout.generation_context).to include("maximum_level" => 3)
    expect(plan.reload.progression_state).to eq("intensity_bias" => 2)
  end
end
