module Adaptations
  class CompletionRecorder
    def initialize(workout:, rpe:, completion_quality:)
      @workout = workout
      @rpe = rpe
      @completion_quality = completion_quality
    end

    def call
      raise ArgumentError, "Only planned structured workouts can be completed" unless @workout.planned? && @workout.structured? && @workout.workout?
      proposal = nil
      PlannedWorkout.transaction do
        @workout.create_workout_feedback!(rpe: @rpe, completion_quality: @completion_quality)
        ftp = RiderProfile.current.ftp_watts || @workout.training_plan.initial_ftp_watts
        snapshot = { steps: @workout.workout_steps.map { |step| { position: step.position, low_watts: (step.target_low_pct_ftp * ftp / 100).round, high_watts: (step.target_high_pct_ftp * ftp / 100).round, end_low_watts: step.end_target_low_pct_ftp && (step.end_target_low_pct_ftp * ftp / 100).round, end_high_watts: step.end_target_high_pct_ftp && (step.end_target_high_pct_ftp * ftp / 100).round } },
          estimated_np_watts: @workout.estimated_np_watts, estimated_if: @workout.estimated_if, estimated_tss: @workout.estimated_tss, estimated_work_kj: @workout.estimated_work_kj }
        @workout.update!(status: :completed, completed_at: Time.current, completed_ftp_watts: ftp, completed_target_snapshot: snapshot)
        evaluation = FeedbackEvaluator.new(@workout).call
        proposal = @workout.training_plan.adaptation_proposals.create!(reason: evaluation[:reason], payload: evaluation[:payload], expires_at: 7.days.from_now) if evaluation
      end
      proposal
    end
  end
end
