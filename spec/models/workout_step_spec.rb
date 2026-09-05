require "rails_helper"

RSpec.describe WorkoutStep, type: :model do
  it "stores ordered, expanded steady steps with percentage targets" do
    step = create(:workout_step)
    expect(step.reload).to have_attributes(target_low_pct_ftp: 60, target_high_pct_ftp: 70)
    duplicate = build(:workout_step, planned_workout: step.planned_workout)
    expect(duplicate).not_to be_valid
    expect_database_rejection(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  [ { duration_seconds: 0 }, { position: 0 }, { target_low_pct_ftp: 0 },
    { target_low_pct_ftp: 80, target_high_pct_ftp: 70 },
    { end_target_low_pct_ftp: 60, end_target_high_pct_ftp: 70 } ].each do |attributes|
    it "rejects invalid steady step #{attributes.inspect} in Rails and PostgreSQL" do
      step = build(:workout_step, **attributes)
      expect(step).not_to be_valid
      expect_database_rejection { step.save!(validate: false) }
    end
  end

  it "requires both ramp endpoint bounds in ascending order" do
    expect(build(:workout_step, :ramp)).to be_valid
    [ { end_target_low_pct_ftp: nil }, { end_target_high_pct_ftp: nil },
      { end_target_low_pct_ftp: 75, end_target_high_pct_ftp: 65 } ].each do |attributes|
      step = build(:workout_step, :ramp, **attributes)
      expect(step).not_to be_valid
      expect_database_rejection { step.save!(validate: false) }
    end
  end
end
