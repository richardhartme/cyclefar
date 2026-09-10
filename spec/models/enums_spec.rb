require "rails_helper"

RSpec.describe "Domain enums", type: :model do
  {
    training_plan: { status: %w[active archived], goal: %w[general_fitness increase_ftp improve_endurance improve_climbing event], discipline: %w[road gravel mtb ultra_endurance], progression_mode: %w[continuous hard_recovery_cycle] },
    target_event: { discipline: %w[road gravel mtb ultra_endurance] },
    plan_phase: { kind: %w[base build speciality taper] },
    availability_template: { source: %w[initial one_week_override from_date_change] },
    availability_slot: { intent: %w[intervals endurance recovery vo2_max threshold sweet_spot tempo] },
    time_off_period: { reason: %w[holiday illness recovery other] },
    planned_workout: { kind: %w[workout ftp_test opener], intent: %w[intervals endurance recovery vo2_max threshold sweet_spot tempo], subtype: %w[recovery endurance tempo sweet_spot threshold vo2_max over_under], status: %w[planned missed completed], detail_status: %w[outline structured] },
    workout_step: { kind: %w[steady ramp] },
    workout_feedback: { completion_quality: %w[as_planned struggled_completed could_not_complete] }
  }.each do |factory, fields|
    fields.each do |field, values|
      it "persists explicit #{factory}.#{field} values and rejects unknown values" do
        record = build(factory)
        expect(record.class.defined_enums.fetch(field.to_s)).to eq(values.index_by(&:itself))
        record.public_send("#{field}=", "unsupported")
        expect(record).not_to be_valid
        expect_database_rejection { record.save!(validate: false) }
      end
    end
  end
end
