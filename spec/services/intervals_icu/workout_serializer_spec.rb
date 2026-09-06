require "rails_helper"

RSpec.describe IntervalsIcu::WorkoutSerializer do
  it "ICU-001 serializes canonical percentage steps using supported workout-builder syntax" do
    workout = create(:planned_workout, :structured)
    step = workout.workout_steps.sole
    step.update!(kind: :ramp, label: "Build", target_low_pct_ftp: 45, target_high_pct_ftp: 55, end_target_low_pct_ftp: 65, end_target_high_pct_ftp: 75)

    payload = described_class.new(workout: workout, ftp_watts: 260).payload(external_id: "cyclefar-workout-#{workout.id}")

    expect(payload).to include(
      category: "WORKOUT", type: "Ride", indoor: true, start_date_local: "#{workout.scheduled_on}T00:00:00",
      external_id: "cyclefar-workout-#{workout.id}", moving_time: 3600, icu_ftp: 260
    )
    expect(payload[:description]).to eq("- Build 1h ramp 50-70%")
    expect(payload[:description]).not_to match(/\\b\\d{3}W\\b/)
  end

  it "uses a percentage range for steady steps" do
    workout = create(:planned_workout, :structured)

    description = described_class.new(workout: workout, ftp_watts: 260).description

    expect(description).to eq("- Steady endurance 1h 60-70%")
  end
end
