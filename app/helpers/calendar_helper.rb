module CalendarHelper
  def workout_profile_svg(workout, detailed: false)
    segments = Workouts::ProfileBuilder.new(steps: workout.workout_steps).call.segments
    total = workout.duration_minutes * 60.0
    width = detailed ? 540 : 180
    height = detailed ? 100 : 44
    inset = detailed ? 12 : 0
    lines = segments.map do |segment|
      x1 = (segment.starts_at_seconds / total * width).round(1)
      x2 = (segment.ends_at_seconds / total * width).round(1)
      y1 = (height - inset - (segment.start_low_pct_ftp + segment.start_high_pct_ftp) / 2.0 / 120 * (height - inset * 2)).round(1)
      y2 = (height - inset - (segment.end_low_pct_ftp + segment.end_high_pct_ftp) / 2.0 / 120 * (height - inset * 2)).round(1)
      tag.line(x1: x1, y1: y1, x2: x2, y2: y2, stroke: "#0f766e", "stroke-width": 2)
    end
    content_tag(:svg, safe_join(lines), viewBox: "0 0 #{width} #{height}", role: "img",
      aria: { label: "Workout intensity profile, shown as percentage of FTP over time" }, class: "mt-2 #{detailed ? 'h-48' : 'h-11'} w-full")
  end
end
