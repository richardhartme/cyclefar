module CalendarHelper
  PROFILE_ZONE_COLORS = {
    recovery: "#94A3B8",
    endurance: "#38BDF8",
    tempo: "#14B8A6",
    sweet_spot: "#22C55E",
    threshold: "#F59E0B",
    vo2_max: "#F97316",
    anaerobic: "#EF4444"
  }.freeze

  def workout_profile_svg(workout, detailed: false)
    segments = Workouts::ProfileBuilder.new(steps: workout.workout_steps).call.segments
    total = workout.duration_minutes * 60.0
    width = detailed ? 540 : 180
    height = detailed ? 100 : 44
    inset = detailed ? 12 : 4
    background = tag.rect(x: 0, y: 0, width: width, height: height, fill: "#f8fafc")
    grid = [ 50, 75, 100 ].map do |percentage|
      tag.line(
        x1: 0,
        y1: y_position(percentage, height, inset),
        x2: width,
        y2: y_position(percentage, height, inset),
        stroke: "#cbd5e1",
        "stroke-width": 1)
    end
    blocks = segments.map do |segment|
      tag.polygon(
        points: block_points(segment, total, width, height, inset),
        fill: profile_zone_color(segment),
        stroke: "#ffffff",
        "stroke-width": 1.5,
        "shape-rendering": "geometricPrecision")
    end
    content_tag(
      :svg,
      safe_join([ background ] + grid + blocks),
      viewBox: "0 0 #{width} #{height}",
      role: "img",
      aria: { label: "Workout power profile, shown as percentage of FTP over time" },
      class: "mt-2 #{detailed ? 'h-48' : 'h-11'} w-full")
  end

  private

  def block_points(segment, total, width, height, inset)
    x1 = (segment.starts_at_seconds / total * width).round(1)
    x2 = (segment.ends_at_seconds / total * width).round(1)
    baseline = height - inset
    [
      [ x1, baseline ],
      [ x1, y_position(target_midpoint(segment.start_low_pct_ftp, segment.start_high_pct_ftp), height, inset) ],
      [ x2, y_position(target_midpoint(segment.end_low_pct_ftp, segment.end_high_pct_ftp), height, inset) ],
      [ x2, baseline ]
    ].map { |point| point.join(",") }.join(" ")
  end

  def target_midpoint(low, high)
    (low + high) / 2.0
  end

  def profile_zone_color(segment)
    percentage = target_midpoint(segment.start_low_pct_ftp, segment.start_high_pct_ftp)

    case percentage
    when ..55 then PROFILE_ZONE_COLORS[:recovery]
    when ..75 then PROFILE_ZONE_COLORS[:endurance]
    when ..87 then PROFILE_ZONE_COLORS[:tempo]
    when ..94 then PROFILE_ZONE_COLORS[:sweet_spot]
    when ..105 then PROFILE_ZONE_COLORS[:threshold]
    when ..120 then PROFILE_ZONE_COLORS[:vo2_max]
    else PROFILE_ZONE_COLORS[:anaerobic]
    end
  end

  def y_position(percentage, height, inset)
    (height - inset - percentage / 120.0 * (height - inset * 2)).round(1)
  end
end
