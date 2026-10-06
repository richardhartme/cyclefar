require "rails_helper"

RSpec.describe Settings::FtpHistory do
  let(:profile) { create(:rider_profile, ftp_watts: 280) }
  let!(:older) { create(:ftp_reading, rider_profile: profile, ftp_watts: 250, effective_on: Date.current - 10) }
  let!(:newest) { create(:ftp_reading, rider_profile: profile, ftp_watts: 280, effective_on: Date.current - 2) }
  subject(:history) { described_class.new(profile: profile) }

  it "CYF-78 edits or deletes older readings without changing the current FTP" do
    history.update!(reading_id: older.id, attributes: { ftp_watts: 260 })
    expect(older.reload.ftp_watts).to eq(260)
    expect(profile.reload.ftp_watts).to eq(280)
    history.destroy!(reading_id: older.id)
    expect(profile.reload.ftp_watts).to eq(280)
    expect(profile.ftp_readings).to contain_exactly(newest)
  end

  it "CYF-78 changes the current FTP when an edit changes date ordering" do
    history.update!(reading_id: older.id, attributes: { effective_on: Date.current })
    expect(profile.reload.ftp_watts).to eq(250)
    history.update!(reading_id: older.id, attributes: { effective_on: Date.current - 20 })
    expect(profile.reload.ftp_watts).to eq(280)
  end

  it "CYF-78 breaks same-date ties by entry ID rather than edit time" do
    history.update!(reading_id: older.id, attributes: { effective_on: newest.effective_on, ftp_watts: 310 })
    expect(profile.reload.ftp_watts).to eq(280)
    history.update!(reading_id: newest.id, attributes: { ftp_watts: 290 })
    expect(profile.reload.ftp_watts).to eq(290)
  end

  it "CYF-78 falls back to the newest remaining reading on deletion and retains the final reading" do
    history.destroy!(reading_id: newest.id)
    expect(profile.reload.ftp_watts).to eq(250)
    expect { history.destroy!(reading_id: older.id) }.to raise_error(ActiveRecord::RecordNotDestroyed)
    expect(profile.reload.ftp_watts).to eq(250)
    expect(older.reload).to be_persisted
  end

  it "CYF-78 rejects invalid edits without changing history or current FTP" do
    [ { ftp_watts: 0 }, { ftp_watts: 260.5 }, { effective_on: nil }, { effective_on: "bad" } ].each do |attributes|
      expect { history.update!(reading_id: newest.id, attributes: attributes) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(newest.reload).to have_attributes(ftp_watts: 280, effective_on: Date.current - 2)
      expect(profile.reload.ftp_watts).to eq(280)
    end
  end

  it "USR-004 rejects a foreign reading without mutating either rider" do
    foreign = create(:ftp_reading)
    before = [ profile, older, newest, foreign, foreign.rider_profile ].map(&:attributes)
    expect { history.update!(reading_id: foreign.id, attributes: { ftp_watts: 350 }) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { history.destroy!(reading_id: foreign.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect([ profile, older, newest, foreign, foreign.rider_profile ].map { |row| row.reload.attributes }).to eq(before)
  end

  it "CYF-78 updates future metrics, watts and exports while preserving canonical steps and completed history" do
    plan = create(:training_plan, user: profile.user, starts_on: Date.current - 20, ends_on: Date.current + 70)
    phase = create(:plan_phase, training_plan: plan, starts_on: plan.starts_on, ends_on: plan.ends_on)
    future = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current + 2)
    past = create(:planned_workout, :structured, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 4)
    completed = create(:planned_workout, :completed, training_plan: plan, plan_phase: phase, scheduled_on: Date.current - 3)
    other = create(:planned_workout, :structured, scheduled_on: Date.current + 3)
    stable = [ past, other, completed, *completed.workout_steps, completed.workout_feedback ].map(&:attributes)
    steps = future.workout_steps.map(&:attributes)

    history.update!(reading_id: newest.id, attributes: { ftp_watts: 300 })
    expect(plan.ftp_watts_for_planning).to eq(300)
    expected = Metrics::WorkoutCalculator.new(steps: future.workout_steps, ftp_watts: 300).call
    expect(future.reload.estimated_work_kj.to_f).to be_within(0.001).of(expected.estimated_work_kj)
    expect(future.workout_steps.reload.map(&:attributes)).to eq(steps)
    expect(Workouts::StepDefinition.from(future.workout_steps.first).target_watts(ftp_watts: plan.ftp_watts_for_planning)).to include(low_watts: 180, high_watts: 210)
    payload = IntervalsIcu::WorkoutSerializer.new(workout: future, ftp_watts: plan.ftp_watts_for_planning).payload(external_id: "cyclefar-workout-#{future.id}")
    expect(payload[:icu_ftp]).to eq(300)
    expect(payload[:joules]).to eq((expected.estimated_work_kj * 1000).round)

    history.destroy!(reading_id: newest.id)
    expect(plan.reload.ftp_watts_for_planning).to eq(250)
    expected = Metrics::WorkoutCalculator.new(steps: future.workout_steps, ftp_watts: 250).call
    expect(future.reload.estimated_work_kj.to_f).to be_within(0.001).of(expected.estimated_work_kj)
    expect(future.workout_steps.reload.map(&:attributes)).to eq(steps)
    expect([ past, other, completed, *completed.workout_steps, completed.workout_feedback ].map { |row| row.reload.attributes }).to eq(stable)
  end

  it "CYF-78 rolls back history and profile changes if metric recalculation fails" do
    allow_any_instance_of(Planning::FtpRecalculator).to receive(:call).and_raise(ArgumentError, "calculation failed")
    expect { history.update!(reading_id: newest.id, attributes: { ftp_watts: 300 }) }.to raise_error(ArgumentError, "calculation failed")
    expect(newest.reload.ftp_watts).to eq(280)
    expect(profile.reload.ftp_watts).to eq(280)
    expect { history.destroy!(reading_id: newest.id) }.to raise_error(ArgumentError, "calculation failed")
    expect(newest.reload).to be_persisted
    expect(profile.reload.ftp_watts).to eq(280)
  end
end
