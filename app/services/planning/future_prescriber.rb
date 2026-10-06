module Planning
  # Prescribes future workouts for date ranges respecting availability and constraints.
  class FuturePrescriber
    attr_reader :slots

    def initialize(plan:, slots:)
      @plan = plan
      @slots = slots.map do |slot|
        attributes = slot.respond_to?(:weekday) ? { weekday: slot.weekday, duration_minutes: slot.duration_minutes, intent: slot.intent } : slot.symbolize_keys
        Availability.new(weekday: Integer(attributes[:weekday]), duration_minutes: Integer(attributes[:duration_minutes]), intent: attributes[:intent])
      end.sort_by(&:weekday).freeze
    end

    def replace!(range, preserve_workout_ids: [])
      @plan.with_lock { replace_under_lock!(range, preserve_workout_ids: preserve_workout_ids) }
    end

    private

    def replace_under_lock!(range, preserve_workout_ids:)
      dates = range.select { |date| date >= Date.current && date.between?(@plan.starts_on, @plan.ends_on) }
      return if dates.empty?

      @generation_contexts = {}
      @pre_break_levels = pre_break_levels
      replaceable_workouts(preserve_workout_ids).where(scheduled_on: dates & blocked_dates(dates)).destroy_all
      replaceable_workouts(preserve_workout_ids).where(kind: :workout, scheduled_on: dates).destroy_all
      prescriptions.filter_map { |item| prepared_prescription(item, dates) }.each do |item|
        next if @plan.planned_workouts.where(scheduled_on: item.scheduled_on).exists?

        phase = @plan.plan_phases.find { |candidate| item.scheduled_on.between?(candidate.starts_on, candidate.ends_on) }
        @plan.planned_workouts.create!(
          plan_phase: phase,
          scheduled_on: item.scheduled_on,
          kind: item.kind,
          intent: item.intent,
          subtype: item.subtype,
          duration_minutes: item.duration_minutes,
          progression_level: item.progression_level,
          generation_context: @generation_contexts.fetch(item.scheduled_on, item.generation_context),
          variation_key: item.definition&.variation_key,
          name: item.name,
          purpose: item.purpose,
          detail_status: :outline,
          estimated_np_watts: item.metrics&.estimated_np_watts,
          estimated_if: item.metrics&.estimated_if,
          estimated_tss: item.metrics&.estimated_tss,
          estimated_work_kj: item.metrics&.estimated_work_kj)
      end
      WorkoutBuilder.new(@plan).call
    end

    def replaceable_workouts(preserve_workout_ids)
      @plan.planned_workouts.planned.where.not(id: preserve_workout_ids)
    end

    def prescriptions
      PlanBuilder.new(ExistingPlanConfiguration.new(plan: @plan, availability: @slots)).preview.prescriptions
    end

    def prepared_prescription(item, dates)
      return unless dates.include?(item.scheduled_on)
      return unless %w[workout opener].include?(item.kind)
      return if time_off_period_for(item.scheduled_on)
      return if return_ramp_period_for(item.scheduled_on) && item.kind != "workout"
      return item unless item.kind == "workout"

      reentry_prescription(item)
    end

    def blocked_dates(dates)
      dates.select { |date| blocked?(date) }
    end

    def blocked?(date)
      time_off_period_for(date) || return_ramp_period_for(date)
    end

    def time_off_period_for(date)
      time_off_periods.find { |period| date.between?(period.starts_on, period.ends_on) }
    end

    def return_ramp_period_for(date)
      time_off_periods.find do |period|
        period.return_ramp_days.present? && date.between?(period.ends_on + 1, period.ends_on + period.return_ramp_days)
      end
    end

    def reentry_prescription(item)
      period = return_ramp_period_for(item.scheduled_on)
      return illness_reentry(item, period) if period

      period = latest_completed_break_before(item.scheduled_on)
      return item unless period

      resume_after_break(item, period)
    end

    def illness_reentry(item, period)
      ramp = ReturnRamp.new(ends_on: period.ends_on, days: period.return_ramp_days)
      stage = ramp.stage_on(item.scheduled_on)
      subtype, level = case stage
      when 0 then [ :recovery, nil ]
      when 1 then [ :endurance, nil ]
      when 2 then [ item.intensity? ? :tempo : :endurance, item.intensity? ? 1 : nil ]
      else [ item.subtype, item.intensity? ? resumed_level(item, period) : nil ]
      end
      band = ramp.target_band(item.scheduled_on, intensity: item.intensity?)
      recalculate(
        item,
        subtype: subtype,
        duration_minutes: reduced_duration(item.duration_minutes, ramp.duration_factor(item.scheduled_on)),
        progression_level: level,
        load_adjustments: band ? { "return_target_band" => band } : {},
        return_ramp_stage: stage + 1,
        purpose: "Return-to-training stage #{stage + 1} after #{period.reason.humanize.downcase}.")
    end

    def resume_after_break(item, period)
      return item unless item.intensity?

      recalculate(
        item,
        subtype: item.subtype,
        duration_minutes: item.duration_minutes,
        progression_level: resumed_level(item, period),
        purpose: "Resuming progression after #{period.reason.humanize.downcase} time off.")
    end

    def resumed_level(item, period)
      baseline = @pre_break_levels.fetch(period.id).fetch(item.subtype, 1)
      ceiling = if period.return_ramp_days
        ReturnRamp.new(ends_on: period.ends_on, days: period.return_ramp_days).progression_level(item.scheduled_on, baseline: baseline)
      else
        baseline + ((item.scheduled_on - period.ends_on - 1) / 7).floor
      end
      biased_level = Training::Progression.level(
        baseline: item.progression_level,
        bias: @plan.progression_state.fetch("intensity_bias", 0).to_i,
        maximum: item.phase == "taper" ? item.generation_context["maximum_level"] : nil)
      [ biased_level, ceiling ].min
    end

    def reduced_duration(duration, factor)
      [ (duration * factor).round, Training::Rules::MINIMUM_DURATION_MINUTES ].max
    end

    def recalculate(item, subtype:, duration_minutes:, progression_level:, purpose:, load_adjustments: {}, return_ramp_stage: nil)
      level = progression_level || 1
      definition = Workouts::Generator.new(
        subtype: subtype,
        duration_minutes: duration_minutes,
        progression_level: level,
        variation_key: Workouts::Variations.default_key(subtype),
        phase: item.phase,
        goal: @plan.goal,
        discipline: @plan.discipline,
        load_adjustments: (item.phase == "taper" ? item.definition.load_adjustments : {}).merge(load_adjustments)).call
      context = item.generation_context.merge("load_adjustments" => definition.load_adjustments)
      if item.intensity?
        context.merge!("baseline_level" => item.progression_level, "maximum_level" => definition.progression_level)
      end
      context["return_ramp_stage"] = return_ramp_stage if return_ramp_stage
      @generation_contexts[item.scheduled_on] = context
      metrics = Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: @plan.ftp_watts_for_planning).call
      item.with(
        subtype: definition.subtype,
        duration_minutes: duration_minutes,
        progression_level: definition.progression_level,
        name: definition.name,
        purpose: purpose,
        main_set_summary: definition.main_set_summary,
        metrics: metrics,
        definition: definition)
    end

    def latest_completed_break_before(date)
      time_off_periods.select { |period| period.ends_on < date }.max_by(&:ends_on)
    end

    def pre_break_levels
      workouts = @plan.planned_workouts.workout.where.not(status: :missed).where.not(progression_level: nil).to_a
      time_off_periods.to_h do |period|
        [ period.id, PreBreakProgression.levels(workouts, before: period.starts_on) ]
      end
    end

    def time_off_periods
      @time_off_periods ||= @plan.time_off_periods.order(:starts_on).to_a
    end
  end
end
