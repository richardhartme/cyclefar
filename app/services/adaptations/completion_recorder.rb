module Adaptations
  # Record completed workout, snapshot targets, and generate adaptation proposal if applicable.
  class CompletionRecorder
    def initialize(workout:, rpe:, completion_quality:)
      @workout = workout
      @rpe = rpe
      @completion_quality = completion_quality
    end

    def call
      proposal = nil

      @workout.training_plan.with_lock do
        @workout.reload
        raise ArgumentError, "Only planned executable workouts can be completed" unless @workout.planned? && !@workout.ftp_test?

        Planning::WorkoutBuilder.new(@workout.training_plan).build_for_completion!(@workout) if @workout.outline?

        @workout.create_workout_feedback!(rpe: @rpe, completion_quality: @completion_quality)
        ftp = @workout.training_plan.ftp_watts_for_planning
        # Overdue structured workouts are outside FTP recalculation's future
        # scope. Freeze coherent metrics at the same FTP as their watt targets.
        metrics = Metrics::WorkoutCalculator.new(steps: @workout.workout_steps, ftp_watts: ftp).call
        PlannedWorkout::METRICS.each { |key| @workout.public_send("#{key}=", metrics.public_send(key)) }

        snapshot = {
          steps: @workout.workout_steps.map { |step|
            {
              position: step.position,
              low_watts: (step.target_low_pct_ftp * ftp / 100).round,
              high_watts: (step.target_high_pct_ftp * ftp / 100).round,
              end_low_watts: step.end_target_low_pct_ftp && (step.end_target_low_pct_ftp * ftp / 100).round,
              end_high_watts: step.end_target_high_pct_ftp && (step.end_target_high_pct_ftp * ftp / 100).round
            }
          },
          estimated_np_watts: @workout.estimated_np_watts,
          estimated_if: @workout.estimated_if,
          estimated_tss: @workout.estimated_tss,
          estimated_work_kj: @workout.estimated_work_kj
        }

        @workout.update!(status: :completed, completed_at: Time.current, completed_ftp_watts: ftp, completed_target_snapshot: snapshot)

        evaluation = FeedbackEvaluator.new(@workout).call
        proposal = ProposalCreator.new(@workout.training_plan).create!(**evaluation) if evaluation
      end
      proposal
    end
  end
end
