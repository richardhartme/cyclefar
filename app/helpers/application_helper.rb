module ApplicationHelper
  def workout_ftp_watts(workout)
    return workout.completed_ftp_watts if workout.completed?

    workout.training_plan.ftp_watts_for_planning
  end

  def ride_duration(seconds)
    hours, remainder = seconds.divmod(3600)
    format("%d:%02d:%02d", hours, *remainder.divmod(60))
  end

  def workout_step_watt_targets(workout, step)
    snapshot = workout.completed_target_snapshot&.fetch("steps", [])&.find { |item| item["position"].to_i == step.position }
    return "#{snapshot["low_watts"]}–#{snapshot["high_watts"]} W" if snapshot

    ftp_watts = workout_ftp_watts(workout)
    "#{(step.target_low_pct_ftp * ftp_watts / 100).round}–#{(step.target_high_pct_ftp * ftp_watts / 100).round} W"
  end
end
