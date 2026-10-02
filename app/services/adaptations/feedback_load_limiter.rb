module Adaptations
  # Read-only generation shared by proposal construction, comparison and accept.
  class FeedbackLoadLimiter
    Candidate = Data.define(:workout, :preview, :fixed_tss, :selected) do
      def scheduled_on = workout.scheduled_on
      def progression_level = preview ? preview.definition.progression_level : workout.progression_level
      def estimated_tss = preview ? preview.metrics.estimated_tss : fixed_tss
      def adjustable? = selected && Training::V1::Rules::LADDERS.key?(workout.subtype.to_sym)
      def reference_tss = selected ? estimated_tss : workout.generation_context.fetch("generated_tss", estimated_tss).to_f
    end

    def initialize(plan)
      @plan = plan
      @context = Planning::V1::LoadContext.new(plan)
    end

    def call(targets)
      selected = targets.to_h { |workout, level, lower_targets| [ workout.id, preview(workout, level, lower_targets) ] }
      last_date = targets.map { |workout, _, _| workout.scheduled_on }.max
      return [] unless last_date

      candidates = @plan.planned_workouts.where("scheduled_on <= ?", last_date.end_of_week)
        .includes(:workout_steps, :plan_phase).order(:scheduled_on).map do |workout|
          proposed = selected[workout.id]
          Candidate.new(
            workout: workout,
            preview: proposed,
            fixed_tss: fixed_tss(workout),
            selected: selected.key?(workout.id))
        end
      reference = nil
      candidates.group_by { |item| item.scheduled_on.beginning_of_week }.each do |week_start, items|
        next unless @context.comparable_week?(week_start, items.map(&:workout))

        if reference && items.any?(&:selected)
          items = Planning::V1::WeeklyLoadCap.reduce(items, limit: Planning::V1::WeeklyLoadCap.limit(reference)) do |candidate|
            level = candidate.progression_level - 1
            candidate.with(preview: preview(candidate.workout, level, false))
          end
          items.select(&:selected).each { |item| selected[item.workout.id] = item.preview }
        end
        reference = items.sum(&:reference_tss)
      end
      targets.map { |workout, _, _| selected.fetch(workout.id) }
    end

    private

    def preview(workout, level, lower_targets)
      level = Training::V1::Progression.level(baseline: level, maximum: @context.maximum_level(workout))
      editor = Workouts::ManualEditor.new(workout)
      proposed = editor.preview(action: :adapt, progression_level: level, lower_targets: lower_targets)
      if workout.progression_level && level < workout.progression_level
        current_tss = Metrics::WorkoutCalculator.new(steps: workout.workout_steps, ftp_watts: @plan.ftp_watts_for_planning).call.estimated_tss
        # Ladder levels describe stimulus, and their TSS is not strictly
        # monotonic. Keep lowering if a nominal reduction raises total load.
        while proposed.metrics.estimated_tss >= current_tss && proposed.definition.progression_level.to_i > 1
          proposed = editor.preview(action: :adapt, progression_level: proposed.definition.progression_level - 1)
        end
      end
      proposed
    end

    def fixed_tss(workout)
      return workout.estimated_tss.to_f if workout.estimated_tss
      return 0 if workout.ftp_test?

      steps = if workout.structured?
        workout.workout_steps
      else
        attributes = { duration_minutes: workout.duration_minutes, phase: workout.plan_phase&.kind || "base", goal: @plan.goal, discipline: @plan.discipline }
        if workout.opener?
          Workouts::OpenerGenerator.new(**attributes).call.steps
        else
          Workouts::Generator.new(
            **attributes,
            subtype: workout.subtype,
            progression_level: workout.progression_level || 1,
            variation_key: workout.variation_key || Workouts::Variations.default_key(workout.subtype)).call.steps
        end
      end
      Metrics::WorkoutCalculator.new(steps: steps, ftp_watts: workout.completed? ? workout.completed_ftp_watts : @plan.ftp_watts_for_planning).call.estimated_tss
    end
  end
end
