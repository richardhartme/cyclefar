module CalendarHelper
  def workout_profile_svg(workout)
    segments = Workouts::ProfileBuilder.new(steps: workout.workout_steps).call.segments
    total = workout.duration_minutes * 60.0
    lines = segments.map do |segment|
      x1 = (segment.starts_at_seconds / total * 180).round(1)
      x2 = (segment.ends_at_seconds / total * 180).round(1)
      y1 = (42 - (segment.start_low_pct_ftp + segment.start_high_pct_ftp) / 2.0 / 120 * 36).round(1)
      y2 = (42 - (segment.end_low_pct_ftp + segment.end_high_pct_ftp) / 2.0 / 120 * 36).round(1)
      tag.line(x1: x1, y1: y1, x2: x2, y2: y2, stroke: "#0f766e", "stroke-width": 2)
    end
    content_tag(:svg, safe_join(lines), viewBox: "0 0 180 44", role: "img", aria: { label: "Workout intensity profile" }, class: "mt-2 h-11 w-full")
  end
end
