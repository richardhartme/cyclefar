require "rails_helper"

RSpec.describe Planning::FtpRecalculator, type: :service do
  let(:plan) { create(:training_plan, starts_on: Date.current - 7, ends_on: Date.current + 70, initial_ftp_watts: 250) }
  let(:phase) { create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on) }

  it "recalculates planned future metrics from the current FTP without changing percentage structure or completed history" do
    Settings::Update.new(profile: RiderProfile.current, attributes: { ftp_watts: 250 }).call
    future = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 2)
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 3)
    percentage_structure = future.workout_steps.map { |step| [ step.target_low_pct_ftp, step.target_high_pct_ftp ] }
    completed_snapshot = completed.completed_target_snapshot.deep_dup
    completed_metrics = completed.slice(:estimated_np_watts, :estimated_if, :estimated_tss, :estimated_work_kj)

    Settings::Update.new(profile: RiderProfile.current, attributes: { ftp_watts: 300 }).call

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
end
