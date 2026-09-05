module Planning
  class PreviewPresenter
    GOAL_LABELS = {
      "general_fitness" => "General Fitness", "increase_ftp" => "Increase FTP", "improve_endurance" => "Improve Endurance",
      "improve_climbing" => "Improve Climbing", "event" => "Prepare for an Event"
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
