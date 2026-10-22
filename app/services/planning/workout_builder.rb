module Planning
  # Builds structured workouts for the next 14 days and applies weekly load limits.
  class WorkoutBuilder
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
      @plan.with_lock { build! }
    end

    # An explicit late-completion request structures only its source. Moving
    # the ordinary horizon backwards would also rewrite unrelated outlines.
    def build_for_completion!(workout)
      @plan.with_lock do
        workout.reload
        unless workout.training_plan_id == @plan.id && workout.planned? && workout.scheduled_on <= @date
          raise ArgumentError, "Only a planned executable workout due today or earlier can be built for completion"
        end
        return if workout.structured?

        build!(workout_id: workout.id)
        workout.reload
      end
    end

    private

    def build!(workout_id: nil)
      @ftp = @plan.ftp_watts_for_planning
      @load_context = LoadContext.new(@plan)
      eligible = @plan.planned_workouts.planned.outline
      eligible = workout_id ? eligible.where(id: workout_id) : eligible.where(scheduled_on: @date..Rules.horizon_end(@date))
      @selected_ids = eligible.pluck(:id)
      candidates = @plan.planned_workouts.where("scheduled_on <= ?", Rules.horizon_end(@date).end_of_week)
        .includes(:plan_phase, :workout_steps).order(:scheduled_on).map { |workout| candidate_for(workout) }
      candidates, warnings = limit_load(candidates)
      candidates.select(&:selected).each { |candidate| persist!(candidate) }
      warnings
    end

    def candidate_for(workout)
      selected = @selected_ids.include?(workout.id)
      if selected || (workout.outline? && workout.estimated_tss.nil?)
        definition = definition_for(workout)
        metrics = Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: @ftp).call
      elsif workout.structured? && workout.estimated_tss.nil?
        ftp = workout.completed? ? workout.completed_ftp_watts : @ftp
        metrics = Metrics::WorkoutCalculator.new(steps: workout.workout_steps, ftp_watts: ftp).call
      end
      Candidate.new(workout: workout, definition: definition, metrics: metrics, selected: selected)
    end

    def definition_for(workout, level: nil, variation: nil)
      eligible = @selected_ids.include?(workout.id)
      Workouts::DefinitionFactory.for(@plan).for_workout(workout) do
        key = if variation
          variation
        elsif eligible
          Workouts::Variations.for_generation(workout.subtype, current_key: workout.variation_key)
        else
          workout.variation_key || Workouts::Variations.default_key(workout.subtype)
        end
        { progression_level: level || (eligible ? biased_level(workout) : workout.progression_level || 1), variation_key: key }
      end
    end

    def biased_level(workout)
      return 1 unless Training::Rules::LADDERS.key?(workout.subtype.to_sym)

      context = workout.generation_context
      maximum = @load_context.maximum_level(workout)
      Training::Progression.level(
        baseline: context["baseline_level"] || workout.progression_level || 1,
        bias: @plan.intensity_bias,
        maximum: maximum)
    end

    def limit_load(candidates)
      reference = nil
      warnings = []
      candidates.group_by { |item| item.scheduled_on.beginning_of_week }.each do |week_start, items|
        next unless @load_context.comparable_week?(week_start, items.map(&:workout))

        in_horizon = week_start <= Rules.horizon_end(@date) && week_start + 6 >= @date
        if reference && (in_horizon || items.any?(&:selected))
          limit = WeeklyLoadCap.limit(reference)
          reduced = WeeklyLoadCap.reduce(items, limit: limit) do |candidate, stage|
            LoadReduction.options(candidate.definition, stage: stage, intent: candidate.workout.intent).map do |definition|
              candidate.with(definition: definition, metrics: Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: @ftp).call)
            end
          end
          items.each_with_index { |item, index| candidates[candidates.index(item)] = reduced[index] }
          items = reduced
          warnings << WeeklyLoadCap.warning(week_start) if items.sum(&:estimated_tss) > limit
        end
        # Explicit one-off edits keep their actual load in this week's total,
        # but must not increase the generated baseline for a later hard week.
        reference = items.sum(&:reference_tss)
      end
      [ candidates, warnings ]
    end

    def persist!(candidate)
      workout, definition, metrics = candidate.workout, candidate.definition, candidate.metrics
      context = workout.generation_context
      workout.apply_definition(
        definition,
        metrics,
        track_generation: true,
        baseline_level: context["baseline_level"] || workout.progression_level,
        purpose: context["maximum_level"] || context["return_ramp_stage"] ? workout.purpose : definition.purpose)
      workout.save!
    end
  end
end
