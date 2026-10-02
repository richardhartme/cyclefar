module Adaptations
  # Validate and resolve adaptation proposal changes; compute updated metrics and bias.
  class ProposalComparison
    UNAVAILABLE_MESSAGE = "Proposal is unavailable. Reject it and review your upcoming workouts.".freeze
    Change = Data.define(:workout, :requested_level, :lower_targets, :current_metrics, :preview)
    Bias = Data.define(:before, :after, :delta)
    Result = Data.define(:changes, :bias, :ftp_watts)

    def initialize(proposal)
      @proposal = proposal
      @plan = proposal.training_plan
    end

    def call
      raise ArgumentError unless [ nil, "feedback" ].include?(@proposal.payload["type"])

      workouts = @plan.planned_workouts.includes(:workout_steps, :plan_phase)
      workouts.find(@proposal.payload.fetch("source_workout_id")) if @proposal.payload.key?("source_workout_id")
      # Resolve the complete set through this plan before generating any summaries.
      raw_changes = @proposal.payload.fetch("changes", [])
      raise ArgumentError unless raw_changes.is_a?(Array)

      targets = raw_changes.map do |change|
        raise ArgumentError unless change.is_a?(Hash)

        workout = workouts.find(change.fetch("planned_workout_id"))
        raise ArgumentError unless workout.planned? && workout.structured? && workout.workout? &&
          workout.scheduled_on.between?(Date.current, Date.current + Training::V1::Rules::FEEDBACK_HORIZON_DAYS - 1)

        [ workout, Integer(change.fetch("progression_level")), change.fetch("lower_targets", false) == true ]
      end
      raise ArgumentError unless targets.map { |workout, _| workout.id }.uniq.length == targets.length

      ftp = @plan.ftp_watts_for_planning
      targets = targets.sort_by { |workout, _| [ workout.scheduled_on, workout.id ] }
      previews = FeedbackLoadLimiter.new(@plan).call(targets)
      changes = targets.zip(previews).map do |(workout, level, lower_targets), preview|
        Change.new(
          workout: workout,
          requested_level: preview.definition.requested_progression_level,
          lower_targets: lower_targets,
          current_metrics: Metrics::WorkoutCalculator.new(steps: workout.workout_steps, ftp_watts: ftp).call,
          preview: preview)
      end
      before = @plan.progression_state.fetch("intensity_bias", 0).to_i
      after = (before + @proposal.payload.fetch("progression_bias", 0).to_i).clamp(*Training::V1::Rules::PROGRESSION_BIAS_BOUNDS)
      Result.new(changes: changes, bias: Bias.new(before: before, after: after, delta: after - before), ftp_watts: ftp)
    rescue ActiveRecord::RecordNotFound, KeyError, ArgumentError, TypeError
      # Payloads are server-owned, but obsolete or malformed IDs must not disclose
      # another plan's records or prevent the rest of the calendar from rendering.
      raise ArgumentError, UNAVAILABLE_MESSAGE
    end
  end
end
