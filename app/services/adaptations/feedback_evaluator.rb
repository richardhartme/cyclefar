module Adaptations
  # Evaluate workout feedback against RPE bands and propose progression adjustments.
  class FeedbackEvaluator
    RPE_BANDS = Training::V1::Rules::RPE_BANDS

    def initialize(workout)
      @workout = workout
      @feedback = workout.workout_feedback
    end

    def call
      return if late_completion_blocked?

      delta, reason = adjustment
      return unless delta

      changes = proposed_changes(delta)
      return if changes.empty?

      proposal = @workout.training_plan.adaptation_proposals.build(payload: { "changes" => changes })
      comparison = ProposalComparison.new(proposal).call
      # A level boundary or exact-duration fit may leave the prescription
      # unchanged. A failed ride must never produce extra generated load.
      changes = comparison.changes.filter_map do |change|
        before = change.current_metrics.estimated_tss
        after = change.preview.metrics.estimated_tss
        next unless delta.positive? ? after > before : after < before

        attributes = { "planned_workout_id" => change.workout.id, "progression_level" => change.requested_level }
        attributes["lower_targets"] = true if change.lower_targets
        attributes
      end
      return if changes.empty?

      { reason: reason, payload: {
        "changes" => changes,
        "progression_bias" => progression_bias,
        "source_workout_id" => @workout.id } }
    end

    private

    def adjustment
      band = RPE_BANDS.fetch(@workout.subtype)
      if !intensity? && (@feedback.could_not_complete? || @feedback.struggled_completed?)
        return [ -1, "Difficult easy ride; reduce targets on the next comparable easy workout within the next 14 days." ]
      end
      return [ -2, "Could not complete; reduce comparable and nearby hard workouts within the next 14 days." ] if @feedback.could_not_complete?
      return [ -1, "Struggled to complete; reduce comparable and nearby broad interval workouts within the next 14 days." ] if @feedback.struggled_completed?
      return [ 1, "RPE was well below the expected range; progress the next comparable workout within the next 14 days." ] if intensity? && @feedback.rpe <= band.begin - 2
      [ -1, "RPE was above the expected range; reduce the next comparable workout within the next 14 days." ] if @feedback.rpe > band.end
    end

    def candidates
      @candidates ||= @workout.training_plan.planned_workouts.planned.structured
        .where(kind: :workout, scheduled_on: Date.current..(Date.current + Training::V1::Rules::FEEDBACK_HORIZON_DAYS - 1))
        .where.not(id: @workout.id).includes(:workout_steps, :plan_phase).order(:scheduled_on).to_a
    end

    def comparable_workout
      same = candidates.find { |item| item.subtype == @workout.subtype }
      return same if same || !intensity?

      family = Training::V1::Rules::COMPARABLE_FAMILIES.find { |members| members.include?(@workout.subtype) }
      candidates.find { |item| family.include?(item.subtype) } ||
        (@workout.intent_intervals? && candidates.find { |item| item.intent_intervals? && intensity?(item) })
    end

    def proposed_changes(delta)
      reductions = {}
      target = comparable_workout
      reductions[target] = delta if target
      if intensity? && (@feedback.struggled_completed? || @feedback.could_not_complete?)
        candidates.each do |item|
          next unless intensity?(item) && item.scheduled_on > @workout.scheduled_on &&
            item.scheduled_on <= @workout.scheduled_on + Training::V1::Rules::NEARBY_HARD_SESSION_DAYS
          next unless @feedback.could_not_complete? || item.intent_intervals?

          # If the comparable session is also nearby, apply the stronger single
          # reduction rather than stacking two reductions onto the same ride.
          reductions[item] = [ reductions.fetch(item, 0), -1 ].min
        end
      end
      reductions.map do |item, adjustment|
        change = { "planned_workout_id" => item.id, "progression_level" => Training::V1::Progression.level(baseline: (item.progression_level || 1) + adjustment) }
        change["lower_targets"] = true unless intensity?(item)
        change
      end
    end

    def late_completion_blocked?
      return false unless @workout.scheduled_on < Date.current

      @workout.training_plan.planned_workouts.completed.where("scheduled_on > ?", @workout.scheduled_on).exists?
    end

    def progression_bias
      return 0 unless intensity?

      recent = @workout.training_plan.planned_workouts.completed.where(subtype: @workout.subtype)
        .order(scheduled_on: :desc, id: :desc).limit(3).includes(:workout_feedback).to_a
      return 0 unless recent.size == 3 && recent.all?(&:workout_feedback)

      band = RPE_BANDS.fetch(@workout.subtype)
      hard = recent.count do |item|
        feedback = item.workout_feedback
        feedback.struggled_completed? || feedback.could_not_complete? || feedback.rpe > band.end
      end
      easy = recent.count { |item| item.workout_feedback.as_planned? && item.workout_feedback.rpe <= band.begin - 2 }
      hard >= 2 ? -1 : easy >= 2 ? 1 : 0
    end

    def intensity?(workout = @workout)
      Training::V1::Rules::LADDERS.key?(workout.subtype.to_sym)
    end
  end
end
