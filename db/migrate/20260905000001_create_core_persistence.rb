class CreateCorePersistence < ActiveRecord::Migration[8.1]
  def change
    create_table :rider_profiles do |t|
      t.integer :ftp_watts, null: false
      t.text :intervals_icu_api_key
      t.timestamps
    end
    add_check_constraint :rider_profiles, "id = 1", name: "rider_profiles_singleton"
    add_check_constraint :rider_profiles, "ftp_watts > 0", name: "rider_profiles_positive_ftp"

    create_table :ftp_readings do |t|
      t.references :rider_profile, null: false, foreign_key: true
      t.integer :ftp_watts, null: false
      t.date :effective_on, null: false
      t.timestamps
    end
    add_check_constraint :ftp_readings, "ftp_watts > 0", name: "ftp_readings_positive_ftp"

    create_table :training_plans do |t|
      t.string :status, null: false, default: "active"
      t.string :goal, null: false
      t.string :discipline, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.boolean :include_base, null: false, default: true
      t.string :progression_mode, null: false
      t.integer :hard_weeks_before_recovery
      t.integer :initial_ftp_watts, null: false
      t.jsonb :progression_state, null: false, default: {}
      t.string :engine_version, null: false, default: "v1"
      t.timestamps
    end
    add_index :training_plans, :status, unique: true, where: "status = 'active'", name: "one_active_training_plan"
    enum_check :training_plans, :status, %w[active archived]
    enum_check :training_plans, :goal, %w[general_fitness increase_ftp improve_endurance improve_climbing event]
    enum_check :training_plans, :discipline, %w[road gravel mtb ultra_endurance]
    enum_check :training_plans, :progression_mode, %w[continuous hard_recovery_cycle]
    date_range_check :training_plans, :starts_on, :ends_on
    add_check_constraint :training_plans, "initial_ftp_watts > 0", name: "training_plans_positive_ftp"
    add_check_constraint :training_plans, "(progression_mode = 'continuous' AND hard_weeks_before_recovery IS NULL) OR (progression_mode = 'hard_recovery_cycle' AND hard_weeks_before_recovery IS NOT NULL AND hard_weeks_before_recovery > 0)", name: "training_plans_recovery_cycle"
    add_check_constraint :training_plans, "jsonb_typeof(progression_state) = 'object'", name: "training_plans_progression_object"

    create_table :target_events do |t|
      t.references :training_plan, null: false, foreign_key: true, index: { unique: true }
      t.string :name, null: false
      t.date :event_on, null: false
      t.string :discipline, null: false
      t.decimal :distance_km, precision: 10, scale: 2
      t.integer :elevation_m
      t.integer :expected_duration_minutes
      t.timestamps
    end
    enum_check :target_events, :discipline, %w[road gravel mtb ultra_endurance]
    add_check_constraint :target_events, "distance_km > 0 AND elevation_m >= 0 AND expected_duration_minutes > 0", name: "target_events_valid_measurements"

    create_table :plan_phases do |t|
      t.references :training_plan, null: false, foreign_key: true
      t.string :kind, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :position, null: false
      t.timestamps
    end
    enum_check :plan_phases, :kind, %w[base build speciality taper]
    date_range_check :plan_phases, :starts_on, :ends_on
    add_check_constraint :plan_phases, "position > 0", name: "plan_phases_positive_position"
    add_index :plan_phases, [ :training_plan_id, :position ], unique: true

    create_table :availability_templates do |t|
      t.references :training_plan, null: false, foreign_key: true
      t.date :effective_from, null: false
      t.date :effective_until
      t.string :source, null: false
      t.timestamps
    end
    enum_check :availability_templates, :source, %w[initial one_week_override from_date_change]
    date_range_check :availability_templates, :effective_from, :effective_until

    create_table :availability_slots do |t|
      t.references :availability_template, null: false, foreign_key: true
      t.integer :weekday, null: false, comment: "ISO weekday: Monday=1 through Sunday=7"
      t.integer :duration_minutes, null: false
      t.string :intent, null: false
      t.timestamps
    end
    add_index :availability_slots, [ :availability_template_id, :weekday ], unique: true
    enum_check :availability_slots, :intent, %w[intervals endurance recovery vo2_max threshold sweet_spot tempo]
    add_check_constraint :availability_slots, "weekday BETWEEN 1 AND 7", name: "availability_slots_weekday"
    add_check_constraint :availability_slots, "duration_minutes >= 30", name: "availability_slots_minimum_duration"

    create_table :time_off_periods do |t|
      t.references :training_plan, null: false, foreign_key: true
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.string :reason, null: false
      t.integer :return_ramp_days
      t.timestamps
    end
    enum_check :time_off_periods, :reason, %w[holiday illness recovery other]
    date_range_check :time_off_periods, :starts_on, :ends_on
    add_check_constraint :time_off_periods, "(reason IN ('illness', 'recovery') AND return_ramp_days IS NOT NULL AND return_ramp_days > 0) OR (reason IN ('holiday', 'other') AND return_ramp_days IS NULL)", name: "time_off_periods_return_ramp"

    create_table :planned_workouts do |t|
      t.references :training_plan, null: false, foreign_key: true
      t.references :plan_phase, foreign_key: true
      t.date :scheduled_on, null: false
      t.string :kind, null: false, default: "workout"
      t.string :intent
      t.string :subtype
      t.integer :duration_minutes
      t.string :name
      t.string :purpose
      t.string :detail_status, null: false, default: "outline"
      t.string :status, null: false, default: "planned"
      t.integer :progression_level
      t.string :variation_key
      t.decimal :estimated_np_watts, precision: 12, scale: 4
      t.decimal :estimated_if, precision: 8, scale: 5
      t.decimal :estimated_tss, precision: 12, scale: 4
      t.decimal :estimated_work_kj, precision: 14, scale: 4
      t.integer :completed_ftp_watts
      t.jsonb :completed_target_snapshot
      t.datetime :completed_at
      t.timestamps
    end
    add_index :planned_workouts, [ :training_plan_id, :scheduled_on ], unique: true
    add_index :planned_workouts, [ :scheduled_on, :status, :detail_status ], name: "planned_workouts_calendar_lookup"
    enum_check :planned_workouts, :kind, %w[workout ftp_test opener]
    enum_check :planned_workouts, :intent, %w[intervals endurance recovery vo2_max threshold sweet_spot tempo]
    enum_check :planned_workouts, :subtype, %w[recovery endurance tempo sweet_spot threshold vo2_max over_under]
    enum_check :planned_workouts, :detail_status, %w[outline structured]
    enum_check :planned_workouts, :status, %w[planned completed]
    add_check_constraint :planned_workouts, "kind = 'ftp_test' OR (duration_minutes IS NOT NULL AND duration_minutes >= 30 AND intent IS NOT NULL)", name: "planned_workouts_minimum_duration"
    add_check_constraint :planned_workouts, "progression_level BETWEEN 1 AND 7", name: "planned_workouts_progression_level"
    add_check_constraint :planned_workouts, "estimated_np_watts >= 0 AND estimated_if >= 0 AND estimated_tss >= 0 AND estimated_work_kj >= 0", name: "planned_workouts_nonnegative_metrics"
    add_check_constraint :planned_workouts, "kind != 'ftp_test' OR (estimated_np_watts IS NULL AND estimated_if IS NULL AND estimated_tss IS NULL AND estimated_work_kj IS NULL AND duration_minutes IS NULL AND detail_status = 'outline')", name: "planned_workouts_ftp_test_no_protocol"
    add_check_constraint :planned_workouts, "(status = 'planned' AND completed_at IS NULL AND completed_ftp_watts IS NULL AND completed_target_snapshot IS NULL) OR (status = 'completed' AND completed_at IS NOT NULL AND (kind = 'ftp_test' OR (detail_status = 'structured' AND completed_ftp_watts IS NOT NULL AND completed_ftp_watts > 0 AND completed_target_snapshot IS NOT NULL AND jsonb_typeof(completed_target_snapshot) = 'object' AND completed_target_snapshot != '{}'::jsonb)))", name: "planned_workouts_completion_snapshot"

    create_table :workout_steps do |t|
      t.references :planned_workout, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :kind, null: false
      t.string :label, null: false
      t.integer :duration_seconds, null: false
      t.decimal :target_low_pct_ftp, precision: 7, scale: 3, null: false
      t.decimal :target_high_pct_ftp, precision: 7, scale: 3, null: false
      t.decimal :end_target_low_pct_ftp, precision: 7, scale: 3
      t.decimal :end_target_high_pct_ftp, precision: 7, scale: 3
      t.string :group_key
      t.integer :group_iteration
      t.timestamps
    end
    add_index :workout_steps, [ :planned_workout_id, :position ], unique: true
    enum_check :workout_steps, :kind, %w[steady ramp]
    add_check_constraint :workout_steps, "position > 0 AND duration_seconds > 0", name: "workout_steps_positive_position_duration"
    add_check_constraint :workout_steps, "target_low_pct_ftp > 0 AND target_low_pct_ftp <= target_high_pct_ftp", name: "workout_steps_target_range"
    add_check_constraint :workout_steps, "(kind = 'steady' AND end_target_low_pct_ftp IS NULL AND end_target_high_pct_ftp IS NULL) OR (kind = 'ramp' AND end_target_low_pct_ftp IS NOT NULL AND end_target_high_pct_ftp IS NOT NULL AND end_target_low_pct_ftp > 0 AND end_target_low_pct_ftp <= end_target_high_pct_ftp)", name: "workout_steps_ramp_endpoints"
    add_check_constraint :workout_steps, "group_iteration > 0", name: "workout_steps_positive_iteration"

    create_table :workout_feedbacks do |t|
      t.references :planned_workout, null: false, foreign_key: true, index: { unique: true }
      t.integer :rpe, null: false
      t.string :completion_quality, null: false
      t.timestamps
    end
    enum_check :workout_feedbacks, :completion_quality, %w[as_planned struggled_completed could_not_complete]
    add_check_constraint :workout_feedbacks, "rpe BETWEEN 1 AND 10", name: "workout_feedbacks_rpe"

    create_table :adaptation_proposals do |t|
      t.references :training_plan, null: false, foreign_key: true
      t.string :reason, null: false
      t.jsonb :payload, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_check_constraint :adaptation_proposals, "jsonb_typeof(payload) = 'object'", name: "adaptation_proposals_payload_object"

    create_table :intervals_icu_syncs do |t|
      t.references :planned_workout, null: false, foreign_key: true, index: { unique: true }
      t.string :external_id, null: false
      t.bigint :intervals_event_id
      t.datetime :last_synced_at
      t.string :payload_digest
      t.timestamps
    end
    add_index :intervals_icu_syncs, :external_id, unique: true
    add_check_constraint :intervals_icu_syncs, "external_id LIKE 'cyclefar-%' AND length(external_id) > 9", name: "intervals_icu_syncs_owned_external_id"
  end

  private

  def enum_check(table, column, values)
    add_check_constraint table, "#{column} IN (#{values.map { |value| quote(value) }.join(', ')})", name: "#{table}_#{column}_values"
  end

  def date_range_check(table, first, last)
    add_check_constraint table, "#{last} >= #{first}", name: "#{table}_ordered_dates"
  end
end
