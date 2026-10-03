module Planning
  # Materializes outlined workouts to structured and applies weekly load limits.
  class HorizonMaterializer
    Candidate = Data.define(:workout, :definition, :metrics, :selected) do
      def scheduled_on = workout.scheduled_on
      def progression_level = definition ? definition.progression_level : workout.progression_level
      def estimated_tss = metrics ? metrics.estimated_tss : workout.estimated_tss.to_f
      def adjustable? = selected && workout.workout?
      def reference_tss = selected ? estimated_tss : workout.generation_context.fetch("generated_tss", estimated_tss).to_f
    end

    def initialize(plan, date: Date.current)
      @plan = plan
      @date = date
    end

    def call
      @plan.with_lock { materialize! }
    end

    # An explicit late-completion request structures only its source. Moving
    # the ordinary horizon backwards would also rewrite unrelated outlines.
    def materialize_for_completion!(workout)
      @plan.with_lock do
        workout.reload
        unless workout.training_plan_id == @plan.id && workout.planned? && !workout.ftp_test? && workout.scheduled_on <= @date
          raise ArgumentError, "Only a planned executable workout due today or earlier can be materialised for completion"
        end
        return if workout.structured?

        materialize!(workout_id: workout.id)
        workout.reload
      end
    end

    private

    def materialize!(workout_id: nil)
      @ftp = @plan.ftp_watts_for_planning
      @load_context = V1::LoadContext.new(@plan)
      eligible = @plan.planned_workouts.planned.outline.where.not(kind: :ftp_test)
      eligible = workout_id ? eligible.where(id: workout_id) : eligible.where(scheduled_on: @date..(@date + 13))
      @selected_ids = eligible.pluck(:id)
      candidates = @plan.planned_workouts.where("scheduled_on <= ?", (@date + 13).end_of_week)
        .includes(:plan_phase, :workout_steps).order(:scheduled_on).map { |workout| candidate_for(workout) }
      candidates, warnings = limit_load(candidates)
      candidates.select(&:selected).each { |candidate| persist!(candidate) }
      warnings
    end

    def candidate_for(workout)
      selected = @selected_ids.include?(workout.id)
      if selected || (!workout.ftp_test? && workout.outline? && workout.estimated_tss.nil?)
        definition = definition_for(workout)
        metrics = Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: @ftp).call
      elsif workout.structured? && workout.estimated_tss.nil?
        ftp = workout.completed? ? workout.completed_ftp_watts : @ftp
        metrics = Metrics::WorkoutCalculator.new(steps: workout.workout_steps, ftp_watts: ftp).call
      end
      Candidate.new(workout: workout, definition: definition, metrics: metrics, selected: selected)
    end

    def definition_for(workout, level: nil, variation: nil)
      attributes = {
        duration_minutes: workout.duration_minutes,
        phase: workout.plan_phase&.kind || "base",
        goal: @plan.goal,
        discipline: @plan.discipline
      }
      return Workouts::OpenerGenerator.new(**attributes).call if workout.opener?

      eligible = @selected_ids.include?(workout.id)
      key = if variation
        variation
      elsif eligible
        Workouts::Variations.for_generation(workout.subtype, current_key: workout.variation_key)
      else
        workout.variation_key || Workouts::Variations.default_key(workout.subtype)
      end
      Workouts::Generator.new(
        **attributes,
        subtype: workout.subtype,
        progression_level: level || (eligible ? biased_level(workout) : workout.progression_level || 1),
        variation_key: key,
        load_adjustments: workout.generation_context.fetch("load_adjustments", {})).call
    end

    def biased_level(workout)
      return 1 unless Training::V1::Rules::LADDERS.key?(workout.subtype.to_sym)

      context = workout.generation_context
      maximum = @load_context.maximum_level(workout)
      Training::V1::Progression.level(
        baseline: context["baseline_level"] || workout.progression_level || 1,
        bias: @plan.progression_state.fetch("intensity_bias", 0).to_i,
        maximum: maximum)
    end

    def limit_load(candidates)
      reference = nil
      warnings = []
      candidates.group_by { |item| item.scheduled_on.beginning_of_week }.each do |week_start, items|
        next unless @load_context.comparable_week?(week_start, items.map(&:workout))

        in_horizon = week_start <= @date + 13 && week_start + 6 >= @date
        if reference && (in_horizon || items.any?(&:selected))
          limit = V1::WeeklyLoadCap.limit(reference)
          reduced = V1::WeeklyLoadCap.reduce(items, limit: limit) do |candidate, stage|
            V1::LoadReduction.options(candidate.definition, stage: stage, intent: candidate.workout.intent).map do |definition|
              candidate.with(definition: definition, metrics: Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: @ftp).call)
            end
          end
          items.each_with_index { |item, index| candidates[candidates.index(item)] = reduced[index] }
          items = reduced
          warnings << V1::WeeklyLoadCap.warning(week_start) if items.sum(&:estimated_tss) > limit
        end
        # Explicit one-off edits keep their actual load in this week's total,
        # but must not increase the generated baseline for a later hard week.
        reference = items.sum(&:reference_tss)
      end
      [ candidates, warnings ]
    end

    def persist!(candidate)
      workout, definition, metrics = candidate.workout, candidate.definition, candidate.metrics
      context = workout.generation_context.merge(
        "baseline_level" => workout.generation_context["baseline_level"] || workout.progression_level,
        "generated_tss" => metrics.estimated_tss,
        "generated_level" => definition.progression_level,
        "load_adjustments" => definition.load_adjustments)
      workout.assign_attributes(
        detail_status: :structured,
        subtype: definition.subtype,
        progression_level: definition.progression_level,
        generation_context: context,
        variation_key: definition.variation_key,
        name: definition.name,
        purpose: workout.generation_context["maximum_level"] ? workout.purpose : definition.purpose,
        estimated_np_watts: metrics.estimated_np_watts,
        estimated_if: metrics.estimated_if,
        estimated_tss: metrics.estimated_tss,
        estimated_work_kj: metrics.estimated_work_kj)
      definition.steps.each { |step| workout.workout_steps.build(step.to_h) }
      workout.save!
    end
  end
end
