module IntervalsIcu
  # Serialize a planned workout to Intervals.icu event payload format.
  class WorkoutSerializer
    def initialize(workout:, ftp_watts:)
      @workout = workout
      @ftp_watts = ftp_watts
    end

    def payload(external_id:)
      {
        category: "WORKOUT",
        type: "Ride",
        indoor: true,
        start_date_local: "#{@workout.scheduled_on}T00:00:00",
        name: @workout.name,
        description: description,
        external_id: external_id,
        moving_time: @workout.duration_minutes * 60,
        icu_ftp: @ftp_watts,
        icu_training_load: @workout.estimated_tss.to_f.round,
        icu_intensity: @workout.estimated_if.to_f.round(3),
        joules: (@workout.estimated_work_kj.to_f * 1000).round
      }
    end

    def description
      @workout.workout_steps.map { |step| "- #{step.label} #{duration(step.duration_seconds)} #{target(step)}" }.join("\n")
    end

    private

    def duration(seconds)
      hours, remaining = seconds.divmod(3600)
      minutes, seconds = remaining.divmod(60)
      [ ("#{hours}h" if hours.positive?), ("#{minutes}m" if minutes.positive?), ("#{seconds}s" if seconds.positive?) ].compact.join
    end

    def target(step)
      return "ramp #{ramp_target(step)}" if step.ramp?

      percentage_range(step.target_low_pct_ftp, step.target_high_pct_ftp)
    end

    def ramp_target(step)
      start = ((step.target_low_pct_ftp + step.target_high_pct_ftp) / 2.0).round
      finish = ((step.end_target_low_pct_ftp + step.end_target_high_pct_ftp) / 2.0).round
      "#{start}-#{finish}%"
    end

    def percentage_range(low, high)
      low == high ? "#{low.to_i}%" : "#{low.to_i}-#{high.to_i}%"
    end
  end
end
