FactoryBot.define do
  factory :rider_profile do
    user
    ftp_watts { 260 }
  end

  factory :ftp_reading do
    rider_profile
    ftp_watts { 260 }
    effective_on { Date.new(2026, 9, 7) }
  end

  factory :training_plan do
    user
    goal { :increase_ftp }
    discipline { :road }
    starts_on { Date.new(2026, 9, 7) }
    ends_on { Date.new(2026, 11, 29) }
    include_base { true }
    progression_mode { :hard_recovery_cycle }
    hard_weeks_before_recovery { 3 }
    initial_ftp_watts { 260 }

    trait :archived do
      status { :archived }
    end
    trait :event do
      goal { :event }
    end
  end

  factory :target_event do
    association :training_plan, :event
    name { "Autumn sportive" }
    event_on { training_plan.ends_on }
    discipline { :road }
  end

  factory :plan_phase do
    training_plan
    kind { :base }
    starts_on { training_plan.starts_on }
    ends_on { starts_on + 27 }
    position { 1 }
  end

  factory :availability_template do
    training_plan
    effective_from { training_plan.starts_on }
    source { :initial }
  end

  factory :availability_slot do
    availability_template
    weekday { 2 }
    duration_minutes { 60 }
    intent { :intervals }
  end

  factory :time_off_period do
    training_plan
    starts_on { training_plan.starts_on + 7 }
    ends_on { starts_on + 6 }
    reason { :holiday }
  end

  factory :planned_workout do
    training_plan
    scheduled_on { training_plan.starts_on + 1 }
    intent { :endurance }
    subtype { :endurance }
    duration_minutes { 60 }
    name { "Endurance 60 min" }
    purpose { "Steady aerobic training" }

    trait :structured do
      detail_status { :structured }
      estimated_np_watts { 169 }
      estimated_if { 0.65 }
      estimated_tss { 42.25 }
      estimated_work_kj { 608.4 }
      after(:build) do |workout|
        workout.workout_steps << build(:workout_step, planned_workout: workout, duration_seconds: workout.duration_minutes * 60)
      end
    end

    trait :completed do
      structured
      after(:create) do |workout|
        create(:workout_feedback, planned_workout: workout)
        # Fixed snapshot fixture; the completion service is a later milestone.
        workout.reload.update!(
          status: :completed,
          completed_at: Time.zone.local(2026, 9, 8, 12),
          completed_ftp_watts: 260,
          completed_target_snapshot: {
            steps: [ { position: 1, low_watts: 156, high_watts: 182 } ],
            estimated_np_watts: 169, estimated_if: 0.65, estimated_tss: 42.25, estimated_work_kj: 608.4
          }
        )
      end
    end

    trait :ftp_test do
      kind { :ftp_test }
      intent { nil }
      subtype { nil }
      duration_minutes { nil }
      name { "FTP Test" }
    end
  end

  factory :workout_step do
    planned_workout
    position { 1 }
    kind { :steady }
    label { "Steady endurance" }
    duration_seconds { 3600 }
    target_low_pct_ftp { 60 }
    target_high_pct_ftp { 70 }

    trait :ramp do
      kind { :ramp }
      target_low_pct_ftp { 45 }
      target_high_pct_ftp { 55 }
      end_target_low_pct_ftp { 65 }
      end_target_high_pct_ftp { 70 }
    end
  end

  factory :workout_feedback do
    planned_workout
    rpe { 4 }
    completion_quality { :as_planned }
  end

  factory :adaptation_proposal do
    training_plan
    reason { "Recent workout was harder than expected" }
    payload { { "changes" => [] } }
    expires_at { Time.zone.local(2026, 9, 9, 12) }
  end

  factory :intervals_icu_sync do
    planned_workout
    external_id { "cyclefar-workout-#{planned_workout.id}" }
  end
end
