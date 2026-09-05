module Adaptations
  class FeedbackEvaluator
    RPE_BANDS = { "recovery" => 1..3, "endurance" => 2..4, "tempo" => 4..6, "sweet_spot" => 5..7,
      "threshold" => 7..9, "vo2_max" => 8..10, "over_under" => 7..9 }.freeze

    def initialize(workout)
      @workout = workout
      @feedback = workout.workout_feedback
    end

    def call
      return if late_completion_blocked?
      delta, reason = adjustment
      return unless delta
      target = comparable_workout
      return unless target

      payload = { "changes" => [ { "planned_workout_id" => target.id, "progression_level" => [ target.progression_level + delta, 1 ].max } ],
        "progression_bias" => progression_bias(delta), "source_workout_id" => @workout.id }
      { reason: reason, payload: payload }
    end

    private

    def adjustment
      band = RPE_BANDS.fetch(@workout.subtype)
      return [ -2, "Could not complete; reduce the next comparable workout." ] if @feedback.could_not_complete?
      return [ -1, "Struggled to complete; reduce the next comparable workout." ] if @feedback.struggled_completed?
      return [ 1, "RPE was well below the expected range; progress the next comparable workout." ] if intensity? && @feedback.rpe <= band.begin - 2
      [ -1, "RPE was above the expected range; reduce the next comparable workout." ] if @feedback.rpe > band.end
    end

    def comparable_workout
      @workout.training_plan.planned_workouts.planned.structured.where("scheduled_on >= ?", Date.current).where.not(id: @workout.id)
        .order(:scheduled_on).find { |item| item.subtype == @workout.subtype && item.workout? }
    end

    def late_completion_blocked?
      return false unless @workout.scheduled_on < Date.current

      @workout.training_plan.planned_workouts.completed.where("scheduled_on > ?", @workout.scheduled_on).exists?
    end

    def intensity?
      %w[tempo sweet_spot threshold vo2_max over_under].include?(@workout.subtype)
    end

    def progression_bias(delta)
      return 0 unless intensity?
      feedbacks = @workout.training_plan.planned_workouts.completed.where(subtype: @workout.subtype).includes(:workout_feedback).map(&:workout_feedback).compact.last(3)
      return 0 unless feedbacks.length == 3

      hard = feedbacks.count { |feedback| feedback.struggled_completed? || feedback.could_not_complete? || feedback.rpe > RPE_BANDS.fetch(@workout.subtype).end }
      easy = feedbacks.count { |feedback| feedback.as_planned? && feedback.rpe <= RPE_BANDS.fetch(@workout.subtype).begin - 2 }
      hard >= 2 ? -1 : easy >= 2 ? 1 : 0
    end
  end
end
