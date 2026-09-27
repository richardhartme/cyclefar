require "rails_helper"

RSpec.describe Planning::FtpRecalculator, type: :service do
  let(:plan) { create(:training_plan, starts_on: Date.current - 7, ends_on: Date.current + 70, initial_ftp_watts: 250) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }

  it "recalculates planned future metrics from the current FTP without changing percentage structure or completed history" do
    Settings::Update.new(profile: plan.user.build_rider_profile, attributes: { ftp_watts: 250 }).call
    future = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 2)
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 3)
    percentage_structure = future.workout_steps.map { |step| [ step.target_low_pct_ftp, step.target_high_pct_ftp ] }
    completed_snapshot = completed.completed_target_snapshot.deep_dup
    completed_metrics = completed.slice(:estimated_np_watts, :estimated_if, :estimated_tss, :estimated_work_kj)

    Settings::Update.new(profile: plan.user.rider_profile, attributes: { ftp_watts: 300 }).call

    expected = Metrics::WorkoutCalculator.new(steps: future.workout_steps, ftp_watts: 300).call
    future.reload
    expect(future.estimated_np_watts.to_f).to be_within(0.001).of(expected.estimated_np_watts)
    expect(future.estimated_if.to_f).to be_within(0.001).of(expected.estimated_if)
    expect(future.estimated_tss.to_f).to be_within(0.001).of(expected.estimated_tss)
    expect(future.estimated_work_kj.to_f).to be_within(0.001).of(expected.estimated_work_kj)
    expect(future.workout_steps.map { |step| [ step.target_low_pct_ftp, step.target_high_pct_ftp ] }).to eq(percentage_structure)
    expect(completed.reload.completed_target_snapshot).to eq(completed_snapshot)
    expect(completed.slice(:estimated_np_watts, :estimated_if, :estimated_tss, :estimated_work_kj)).to eq(completed_metrics)
  end

  it "leaves another user's future workouts and FTP history alone" do
    Settings::Update.new(profile: plan.user.build_rider_profile, attributes: { ftp_watts: 250 }).call
    own_future = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 2)
    own_completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 3)
    own_snapshot = own_completed.completed_target_snapshot.deep_dup
    own_completed_steps = own_completed.workout_steps.map(&:attributes)
    other_plan = create(:training_plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    other_profile = Settings::Update.new(profile: other_plan.user.build_rider_profile, attributes: { ftp_watts: 300, intervals_icu_api_key: "other-rider-secret" }).call
    other_phase = create(:plan_phase, training_plan: other_plan, starts_on: other_plan.starts_on, ends_on: other_plan.ends_on)
    other_workout = create(:planned_workout, :structured, training_plan: other_plan, plan_phase: other_phase, scheduled_on: Date.current + 2)
    other_completed = create(:planned_workout, :completed, training_plan: other_plan, plan_phase: other_phase, scheduled_on: Date.current + 3)
    original_metrics = other_workout.slice(:estimated_np_watts, :estimated_if, :estimated_tss, :estimated_work_kj)
    other_history = other_completed.attributes.deep_dup
    other_snapshot = other_completed.completed_target_snapshot.deep_dup
    other_completed_steps = other_completed.workout_steps.map(&:attributes)
    other_plan_attributes = other_plan.attributes.deep_dup

    Settings::Update.new(profile: plan.user.rider_profile, attributes: { ftp_watts: 320 }).call

    expected = Metrics::WorkoutCalculator.new(steps: own_future.workout_steps, ftp_watts: 320).call
    expect(own_future.reload.estimated_np_watts).to be_within(0.001).of(expected.estimated_np_watts)
    expect(own_future.estimated_work_kj).to be_within(0.001).of(expected.estimated_work_kj)
    expect(plan.ftp_watts_for_planning).to eq(320)
    expect(other_plan.ftp_watts_for_planning).to eq(300)
    presentation = Object.new.extend(ApplicationHelper)
    expect(presentation.workout_step_watt_targets(own_future, own_future.workout_steps.first)).to eq("192–224 W")
    expect(presentation.workout_step_watt_targets(other_workout, other_workout.workout_steps.first)).to eq("180–210 W")
    expect(presentation.workout_step_watt_targets(own_completed, own_completed.workout_steps.first)).to eq("156–182 W")
    expect(presentation.workout_step_watt_targets(other_completed, other_completed.workout_steps.first)).to eq("156–182 W")
    expect(own_completed.reload.completed_target_snapshot).to eq(own_snapshot)
    expect(own_completed.workout_steps.map(&:attributes)).to eq(own_completed_steps)
    expect(other_profile.reload).to have_attributes(ftp_watts: 300, intervals_icu_api_key: "other-rider-secret")
    expect(other_profile.ftp_readings.pluck(:ftp_watts)).to eq([ 300 ])
    expect(other_workout.reload.slice(*original_metrics.keys)).to eq(original_metrics)
    expect(other_completed.reload.attributes).to eq(other_history)
    expect(other_completed.completed_target_snapshot).to eq(other_snapshot)
    expect(other_completed.workout_steps.map(&:attributes)).to eq(other_completed_steps)
    expect(other_plan.reload.attributes).to eq(other_plan_attributes)
  end
end
