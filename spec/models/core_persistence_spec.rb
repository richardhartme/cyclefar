require "rails_helper"

RSpec.describe "Core persistence", type: :model do
  describe "PLN-014 plans" do
    it "allows one active plan and multiple archived plans" do
      create(:training_plan)
      expect(build(:training_plan)).not_to be_valid
      create_list(:training_plan, 2, :archived)
      expect_database_rejection(ActiveRecord::RecordNotUnique) { build(:training_plan).save!(validate: false) }
      expect(TrainingPlan.active.count).to eq(1)
      expect(TrainingPlan.archived.count).to eq(2)
    end

    it "rejects reactivation while another plan is active" do
      create(:training_plan)
      archive = create(:training_plan, :archived)
      expect(archive.update(status: :active)).to be(false)
      expect_database_rejection(ActiveRecord::RecordNotUnique) { archive.update_columns(status: "active") }
    end

    it "persists engine version and protects confirmed configuration" do
      plan = create(:training_plan)
      expect(plan.reload.engine_version).to eq("v1")
      expect(plan.update(goal: :improve_endurance)).to be(false)
      expect(plan.reload.update(status: :archived)).to be(true)
    end

    it "PLN-012 requires a positive hard-week count only for cyclic progression" do
      expect(build(:training_plan, hard_weeks_before_recovery: 0)).not_to be_valid
      expect(build(:training_plan, progression_mode: :continuous)).not_to be_valid
      expect(build(:training_plan, progression_mode: :continuous, hard_weeks_before_recovery: nil)).to be_valid
      expect_database_rejection { build(:training_plan, hard_weeks_before_recovery: nil).save!(validate: false) }
    end

    it "rejects reversed dates and invalid FTP" do
      plan = build(:training_plan)
      plan.ends_on = plan.starts_on - 1
      expect(plan).not_to be_valid
      expect_database_rejection { plan.save!(validate: false) }
      expect(build(:training_plan, initial_ftp_watts: 0)).not_to be_valid
    end
  end

  describe "PLN-022 target events" do
    it "persists one event per plan with optional measurements" do
      event = create(:target_event)
      expect(event).to be_valid
      duplicate = build(:target_event, training_plan: event.training_plan)
      expect(duplicate).not_to be_valid
      expect_database_rejection(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
      expect(event.update(name: "Changed event")).to be(false)
    end

    it "requires an event goal, matching date and valid measurements" do
      expect(build(:target_event, training_plan: build(:training_plan))).not_to be_valid
      expect(build(:target_event, event_on: Date.new(2027, 1, 1))).not_to be_valid
      [ { distance_km: 0 }, { elevation_m: -1 }, { expected_duration_minutes: 0 }, { name: nil } ].each do |attributes|
        expect(build(:target_event, **attributes)).not_to be_valid
      end
    end
  end

  describe "PLN-020 phases" do
    it "requires non-overlapping, contiguous neighbours inside plan dates" do
      first = create(:plan_phase)
      second = build(
        :plan_phase,
        training_plan: first.training_plan,
        kind: :build,
        position: 2,
        starts_on: first.ends_on + 1,
        ends_on: first.ends_on + 28)
      expect(second).to be_valid
      second.starts_on += 1
      expect(second).not_to be_valid
      second.starts_on = first.ends_on
      expect(second).not_to be_valid
      first.ends_on = first.training_plan.ends_on + 1
      expect(first).not_to be_valid
    end

    it "rejects duplicate positions, unsupported Base and non-event taper" do
      phase = create(:plan_phase)
      duplicate = build(:plan_phase, training_plan: phase.training_plan)
      expect_database_rejection(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
      expect(build(:plan_phase, kind: :taper)).not_to be_valid
      expect(build(:plan_phase, training_plan: build(:training_plan, include_base: false))).not_to be_valid
    end
  end

  describe "PLN-011 / SCH-001 availability" do
    it "uses ISO weekdays, exact durations and one slot per weekday" do
      slot = create(:availability_slot)
      expect(slot.weekday).to eq(2)
      expect(slot.availability_template.availability_slots.count).to eq(1)
      duplicate = build(:availability_slot, availability_template: slot.availability_template)
      expect(duplicate).not_to be_valid
      expect_database_rejection(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
      [ { weekday: 0 }, { weekday: 8 }, { duration_minutes: 29 }, { duration_minutes: 45.5 } ].each do |attributes|
        expect(build(:availability_slot, **attributes)).not_to be_valid
      end
      expect(build(:availability_slot, duration_minutes: 47)).to be_valid
    end

    it "allows open-ended templates and bounded Monday-Sunday overrides" do
      expect(build(:availability_template)).to be_valid
      template = build(:availability_template, source: :one_week_override)
      expect(template).not_to be_valid
      template.effective_until = template.effective_from + 6
      expect(template).to be_valid
      template.effective_from += 1
      expect(template).not_to be_valid
    end
  end

  describe "OFF-001 time off" do
    %i[illness recovery].each do |reason|
      it "requires a positive return ramp for #{reason}" do
        expect(build(:time_off_period, reason: reason)).not_to be_valid
        expect(build(:time_off_period, reason: reason, return_ramp_days: 3)).to be_valid
        expect_database_rejection { build(:time_off_period, reason: reason).save!(validate: false) }
      end
    end

    it "rejects ramps for holiday/other and overlapping or out-of-plan ranges" do
      period = create(:time_off_period)
      expect(build(:time_off_period, reason: :other, return_ramp_days: 2)).not_to be_valid
      expect(build(:time_off_period, training_plan: period.training_plan)).not_to be_valid
      period.starts_on = period.training_plan.starts_on - 1
      expect(period).not_to be_valid
    end
  end

  describe "FBK-001 feedback" do
    it "requires integer RPE 1-10 and one record per workout" do
      feedback = create(:workout_feedback)
      duplicate = build(:workout_feedback, planned_workout: feedback.planned_workout)
      expect(duplicate).not_to be_valid
      expect_database_rejection(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
      [ 0, 11, 4.5, nil ].each { |rpe| expect(build(:workout_feedback, rpe: rpe)).not_to be_valid }
      expect_database_rejection { feedback.update_columns(rpe: 11) }
    end
  end

  describe "FBK-002 proposal persistence" do
    it "stores proposed data without changing a workout and requires an object payload" do
      workout = create(:planned_workout)
      original = workout.attributes
      proposal = create(:adaptation_proposal, training_plan: workout.training_plan)
      expect(workout.reload.attributes).to eq(original)
      expect(proposal.reload.payload).to eq("changes" => [])
      proposal.payload = []
      expect(proposal).not_to be_valid
      expect_database_rejection { proposal.save!(validate: false) }
    end
  end

  describe "BRD-001 / ICU-001 sync metadata" do
    it "requires unique CycleFar-owned external IDs and stable identity" do
      sync = create(:intervals_icu_sync)
      expect(sync.reload.external_id).to start_with("cyclefar-")
      expect(sync.update(external_id: "cyclefar-replacement")).to be(false)
      expect_database_rejection { sync.update_columns(external_id: "unrelated-event") }
      duplicate = build(:intervals_icu_sync, planned_workout: sync.planned_workout, external_id: "cyclefar-another")
      expect_database_rejection(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
      other = create(:planned_workout, training_plan: sync.planned_workout.training_plan, scheduled_on: sync.planned_workout.scheduled_on + 1)
      expect_database_rejection(ActiveRecord::RecordNotUnique) do
        build(:intervals_icu_sync, planned_workout: other, external_id: sync.reload.external_id).save!(validate: false)
      end
    end
  end
end
