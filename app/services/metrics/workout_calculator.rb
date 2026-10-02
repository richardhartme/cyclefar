require_relative "../training/v1/rules"
require_relative "../workouts/step_sequence"

module Metrics
  # Calculates workout metrics (power, NP, IF, TSS, work) from step definitions and FTP.
  class WorkoutCalculator
    Result = Data.define(:duration_seconds, :average_power_watts, :estimated_np_watts, :estimated_if, :estimated_tss, :estimated_work_kj)

    def initialize(steps:, ftp_watts:)
      Workouts::StepDefinition.validate_ftp!(ftp_watts)
      @steps = Workouts::StepSequence.normalize(steps)
      @ftp_watts = ftp_watts
    end

    def call
      window_size = Training::V1::Rules::NP_WINDOW_SECONDS
      window = Array.new(window_size, 0.0)
      window_sum = power_sum = fourth_power_sum = 0.0
      count = 0
      @steps.each do |step|
        step.duration_seconds.times do |second|
          power = @ftp_watts * step.representative_pct_at(second) / 100.0
          slot = count % window_size
          window_sum += power - window[slot]
          window[slot] = power
          count += 1
          power_sum += power
          # Use a growing window for the first 29 samples, then a rolling 30s
          # window across all step boundaries (TRAINING_ENGINE.md section 25).
          fourth_power_sum += (window_sum / [ count, window_size ].min)**4
        end
      end
      np = (fourth_power_sum / count)**0.25
      intensity = np / @ftp_watts
      Result.new(
        duration_seconds: count,
        average_power_watts: power_sum / count,
        estimated_np_watts: np,
        estimated_if: intensity,
        estimated_tss: count / 3600.0 * intensity**2 * 100,
        estimated_work_kj: power_sum / 1000.0)
    end
  end
end
