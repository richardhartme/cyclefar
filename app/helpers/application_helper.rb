module ApplicationHelper
  def workout_ftp_watts(workout)
    return workout.completed_ftp_watts if workout.completed?

    workout.training_plan.ftp_watts_for_planning
  end

  def ride_duration(seconds)
    hours, remainder = seconds.divmod(3600)
    format("%d:%02d:%02d", hours, *remainder.divmod(60))
  end

  # GAR-011: a merged upload keeps its upload label.
  def activity_source_label(activity)
    activity.garmin? ? "Garmin Connect" : "Uploaded FIT"
  end

  # Start time, moving duration and, with power, TSS: enough to tell rides apart.
  def ride_summary(activity)
    parts = [ activity.started_at.in_time_zone.strftime("%a %-d %b, %H:%M"), ride_duration(activity.moving_seconds) ]
    parts << "#{activity.tss.round} TSS" if activity.power?
    parts.join(" · ")
  end

  def workout_step_watt_targets(workout, step)
    snapshot = workout.completed_target_snapshot&.fetch("steps", [])&.find { |item| item["position"].to_i == step.position }
    return "#{snapshot["low_watts"]}–#{snapshot["high_watts"]} W" if snapshot

    ftp_watts = workout_ftp_watts(workout)
    "#{(step.target_low_pct_ftp * ftp_watts / 100).round}–#{(step.target_high_pct_ftp * ftp_watts / 100).round} W"
  end
end
