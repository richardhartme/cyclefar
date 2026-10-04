module CalendarHelper
  WORKOUT_CARD_COLORS = {
    recovery: "bg-slate-50 border-slate-300",
    endurance: "bg-sky-50 border-sky-300",
    tempo: "bg-teal-50 border-teal-300",
    sweet_spot: "bg-green-50 border-green-300",
    threshold: "bg-amber-50 border-amber-300",
    vo2_max: "bg-orange-50 border-orange-300",
    over_under: "bg-rose-50 border-rose-300",
    opener: "bg-violet-50 border-violet-300",
    ftp_test: "bg-indigo-50 border-indigo-300"
  }.freeze

  def workout_card_colors(workout)
    return "bg-slate-100 border-slate-300" if workout.missed?

    type = workout.workout? ? workout.subtype : workout.kind
    WORKOUT_CARD_COLORS.fetch(type.to_sym, WORKOUT_CARD_COLORS[:recovery])
  end

  def workout_type_label(workout)
    return "Opener" if workout.opener?

    Training::V1::Rules::SUBTYPE_NAMES.fetch(workout.subtype.to_sym)
  end

  def workout_main_set_entries(workout)
    steps = workout.workout_steps.select { |step| %w[main activation].include?(step.group_key) }
    # Older canonical structures can lack grouping metadata. Exclude known
    # preparation/recovery groups rather than inventing a generated main set.
    steps = workout.workout_steps.reject { |step| %w[warm_up cool_down recovery filler].include?(step.group_key) } if steps.empty?
    steps.group_by { |step|
      [ step.label, step.duration_seconds, step.kind, step.target_low_pct_ftp, step.target_high_pct_ftp,
        step.end_target_low_pct_ftp, step.end_target_high_pct_ftp ]
    }.values.map do |repetitions|
      step = repetitions.first
      minutes, seconds = step.duration_seconds.divmod(60)
      duration = [ ("#{minutes} min" if minutes.positive?), ("#{seconds} sec" if seconds.positive?) ].compact.join(" ")
      duration = "#{repetitions.size} × #{duration}" if repetitions.size > 1
      { summary: "#{step.label} · #{duration}", targets: workout_card_step_targets(workout, step) }
    end
  end

  def workout_card_step_targets(workout, step)
    targets = if workout.completed?
      workout.completed_target_snapshot.fetch("steps").find { |item| item.fetch("position").to_i == step.position }
    else
      Workouts::StepDefinition.from(step).target_watts(ftp_watts: workout_ftp_watts(workout)).stringify_keys
    end
    range = "#{targets.fetch('low_watts')}–#{targets.fetch('high_watts')}"
    range += " → #{targets.fetch('end_low_watts')}–#{targets.fetch('end_high_watts')}" if step.ramp?
    "#{range} W"
  end

  PROFILE_ZONE_COLORS = {
    recovery: "#94A3B8",
    endurance: "#38BDF8",
    tempo: "#14B8A6",
    sweet_spot: "#22C55E",
    threshold: "#F59E0B",
    vo2_max: "#F97316",
    anaerobic: "#EF4444"
  }.freeze

  def workout_step_color(step)
    zone_color(target_midpoint(step.target_low_pct_ftp, step.target_high_pct_ftp))
  end

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
        stroke: "none",
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
    zone_color(target_midpoint(segment.start_low_pct_ftp, segment.start_high_pct_ftp))
  end

  def zone_color(percentage)
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
