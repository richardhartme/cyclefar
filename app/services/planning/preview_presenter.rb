module Planning
  # Formats preview data for display: labels, descriptions and aggregated metrics.
  class PreviewPresenter
    GOAL_LABELS = {
      "general_fitness" => "General Fitness", "increase_ftp" => "Increase FTP", "improve_endurance" => "Improve Endurance",
      "improve_climbing" => "Improve Climbing", "event" => "Prepare for an Event"
    }.freeze
    GOAL_DESCRIPTIONS = {
      "general_fitness" => "Balances aerobic endurance with varied intensity across the plan.",
      "increase_ftp" => "Prioritises threshold, VO2 Max and over-under progression to raise sustainable power.",
      "improve_endurance" => "Emphasises endurance volume with aerobic tempo and Sweet Spot work.",
      "improve_climbing" => "Prioritises threshold, VO2 Max and over-under sessions for sustained climbing efforts.",
      "event" => "Uses your event date and discipline to shape speciality sessions, taper and opener."
    }.freeze
    DISCIPLINE_LABELS = { "road" => "Road", "gravel" => "Gravel", "mtb" => "MTB", "ultra_endurance" => "Ultra / Endurance" }.freeze

    def initialize(preview)
      @preview = preview
    end

    def goal_label = GOAL_LABELS.fetch(@preview.configuration.goal)
    def discipline_label = DISCIPLINE_LABELS.fetch(@preview.configuration.discipline)
    def date_range = "#{@preview.starts_on.to_fs(:long)} – #{@preview.ends_on.to_fs(:long)}"
    def phase_label(phase) = phase.kind.humanize
    def week_duration(week) = "#{week.duration_minutes} min"
    def week_tss(week) = format("%.0f TSS", week.estimated_tss)
    def week_work(week) = format("%.0f kJ", week.estimated_work_kj)
    def event_summary
      return unless @preview.configuration.event?

      [ @preview.configuration.event_name, DISCIPLINE_LABELS.fetch(@preview.configuration.event_discipline), @preview.configuration.event_on.to_fs(:long) ].join(" · ")
    end
  end
end
