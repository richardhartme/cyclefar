module Workouts
  class Mover
    Result = Data.define(:workout, :regenerated, :warnings)
    Candidate = Data.define(:workout, :definition, :metrics) do
      def scheduled_on = workout.scheduled_on
      def progression_level = definition.progression_level
      def estimated_tss = metrics.estimated_tss
      def adjustable? = workout.workout?
    end

    def initialize(workout)
      @workout = workout
      @plan = workout.training_plan
    end

    def move_to!(destination:)
      @plan.with_lock do
        @workout.reload
        @periods = nil
        raise ArgumentError, "Completed workouts cannot be moved; only planned workouts can be moved" unless @workout.planned?
        raise ArgumentError, "Only workouts in an active plan can be moved" unless @plan.active?

        phase = DestinationValidator.new(@plan).validate!(destination, excluding_workout: @workout)
        regenerate = @workout.plan_phase_id != phase.id ||
          (@workout.scheduled_on - destination).abs > Planning::Rules::MOVE_STRUCTURE_WINDOW_DAYS ||
          reduced_context(@workout.scheduled_on) != reduced_context(destination)
        @workout.update!(scheduled_on: destination, plan_phase: phase)
        materialize = @workout.outline? && destination.between?(Date.current, Date.current + 13)
        if regenerate || materialize
          regenerate!(fresh_context: regenerate, materialize: materialize)
        elsif @workout.structured?
          refresh_metrics!
        end
        week = Planning::WeeklyLoadReview.new(@plan).call.find { |item| item.starts_on == destination.beginning_of_week }
        Result.new(workout: @workout, regenerated: regenerate, warnings: [ week&.warning ].compact)
      end
    end

    private

    def refresh_metrics!
      metrics = Metrics::WorkoutCalculator.new(steps: @workout.workout_steps, ftp_watts: @plan.ftp_watts_for_planning).call
      @workout.update!(PlannedWorkout::METRICS.to_h { |key| [ key, metrics.public_send(key) ] })
    end

    def regenerate!(fresh_context:, materialize:)
      @ftp = @plan.ftp_watts_for_planning
      context = fresh_context ? destination_context : @workout.generation_context.dup
      baseline = context["baseline_level"] || @workout.progression_level || 1
      maximum = fresh_context ? context["maximum_level"] : Planning::LoadContext.new(@plan).maximum_level(@workout)
      level = Training::Progression.level(baseline: baseline, bias: @plan.progression_state.fetch("intensity_bias", 0).to_i, maximum: maximum)
      candidate = limit_load(candidate_for(level, load_adjustments: context.fetch("load_adjustments", {})))
      definition, metrics = candidate.definition, candidate.metrics
      # Destination references replace source-week ceilings. The saved baseline
      # also prevents bias stacking when a moved outline later materialises.
      context.merge!(
        "baseline_level" => baseline,
        "generated_level" => definition.progression_level,
        "generated_tss" => metrics.estimated_tss,
        "load_adjustments" => definition.load_adjustments)
      if definition.progression_level && definition.progression_level < level
        context["maximum_level"] = [ maximum || 7, definition.progression_level ].min
      end
      structured = @workout.structured? || materialize
      @workout.workout_steps.destroy_all
      @workout.assign_attributes(
        detail_status: structured ? :structured : :outline,
        progression_level: definition.progression_level,
        generation_context: context,
        variation_key: definition.variation_key,
        name: definition.name,
        purpose: definition.purpose,
        estimated_np_watts: metrics.estimated_np_watts,
        estimated_if: metrics.estimated_if,
        estimated_tss: metrics.estimated_tss,
        estimated_work_kj: metrics.estimated_work_kj)
      definition.steps.each { |step| @workout.workout_steps.build(step.to_h) } if structured
      @workout.save!
    end

    def candidate_for(level, load_adjustments: {})
      attributes = { duration_minutes: @workout.duration_minutes, phase: @workout.plan_phase.kind, goal: @plan.goal, discipline: @plan.discipline }
      definition = if @workout.opener?
        OpenerGenerator.new(**attributes).call
      else
        Generator.new(
          **attributes,
          subtype: @workout.subtype,
          progression_level: level,
          variation_key: @workout.variation_key || Variations.default_key(@workout.subtype),
          load_adjustments: load_adjustments).call
      end
      Candidate.new(
        workout: @workout,
        definition: definition,
        metrics: Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: @ftp).call)
    end

    def limit_load(candidate)
      review = Planning::WeeklyLoadReview.new(@plan)
      week = review.call.find { |item| item.starts_on == @workout.scheduled_on.beginning_of_week }
      return candidate unless week.limit

      fixed_tss = week.workouts.reject { |workout| workout.id == @workout.id }.sum { |workout| review.estimated_tss(workout) }
      Planning::WeeklyLoadCap.reduce([ candidate ], limit: week.limit - fixed_tss) do |item, stage|
        # Explicit Move promises to retain the rider's selected subtype.
        Planning::LoadReduction.options(item.definition, stage: stage, intent: @workout.subtype).map do |definition|
          item.with(definition: definition, metrics: Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: @ftp).call)
        end
      end.sole
    end

    def destination_context
      return {} unless @workout.workout? && Training::Rules::LADDERS.key?(@workout.subtype.to_sym)

      phase = @workout.plan_phase
      baseline = Planning::PhaseProgression.level(date: @workout.scheduled_on, kind: phase.kind, starts_on: phase.starts_on, ends_on: phase.ends_on)
      maximum = destination_maximum
      { "baseline_level" => baseline }.tap { |context| context["maximum_level"] = maximum if maximum }
    end

    def destination_maximum
      date = @workout.scheduled_on
      ceilings = []
      ceilings << Planning::Rules::RECOVERY_MAXIMUM_LEVEL if recovery_week?(date)
      ceilings << Planning::Rules::PHASE_LEVELS[:taper].end if @workout.plan_phase.kind_taper?
      if (period = periods.select { |item| item.ends_on < date }.max_by(&:ends_on))
        reached = @plan.planned_workouts.where("scheduled_on < ?", period.starts_on).where.not(id: @workout.id).map do |workout|
          workout.generation_context.fetch("generated_level", workout.progression_level)
        end.compact.max || 1
        week_offset = ((date - period.ends_on - 1) / 7).to_i
        if period.return_ramp_days && date <= period.ends_on + period.return_ramp_days
          stage = return_stage(period, date)
          # Explicit Move retains subtype/duration while bounding the level by
          # the destination's return-to-training ceiling.
          ceilings << (stage < 3 ? 1 : [ reached - 1 + week_offset, 1 ].max)
        else
          ceilings << [ reached + week_offset, 1 ].max
        end
      end
      ceilings.min
    end

    def reduced_context(date)
      period = periods.select { |item| item.ends_on < date }.max_by(&:ends_on)
      stage = return_stage(period, date) if period&.return_ramp_days && date <= period.ends_on + period.return_ramp_days
      [ recovery_week?(date), period&.id, stage ]
    end

    def return_stage(period, date)
      [ ((date - period.ends_on - 1) * 4 / period.return_ramp_days).floor, 3 ].min
    end

    def recovery_week?(date)
      return false unless @plan.hard_recovery_cycle?

      index = ((date.beginning_of_week - @plan.starts_on.beginning_of_week) / 7).to_i
      index % (@plan.hard_weeks_before_recovery + 1) == @plan.hard_weeks_before_recovery
    end

    def periods
      @periods ||= @plan.time_off_periods.order(:starts_on).to_a
    end
  end
end
