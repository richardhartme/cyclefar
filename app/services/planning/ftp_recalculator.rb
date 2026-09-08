module Planning
  class FtpRecalculator
    def initialize(ftp_watts:, effective_on: Date.current)
      @ftp_watts = ftp_watts
      @effective_on = effective_on
    end

    def call
      TrainingPlan.active.find_each do |plan|
        plan.planned_workouts.planned.structured.where(kind: %w[workout opener]).where("scheduled_on >= ?", @effective_on).includes(:workout_steps).find_each do |workout|
          metrics = Metrics::WorkoutCalculator.new(steps: workout.workout_steps, ftp_watts: @ftp_watts).call
          workout.update!(
            estimated_np_watts: metrics.estimated_np_watts,
            estimated_if: metrics.estimated_if,
            estimated_tss: metrics.estimated_tss,
            estimated_work_kj: metrics.estimated_work_kj)
        end
      end
    end
  end
end
