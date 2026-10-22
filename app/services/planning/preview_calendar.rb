module Planning
  # Week-level facts about a plan preview: which weeks are partial, recovery or
  # taper weeks, and the weekly summaries built from prescriptions.
  class PreviewCalendar
    def initialize(configuration:, phases:, recovery_flags:)
      @configuration = configuration
      @phases = phases
      @recovery_flags = recovery_flags
    end

    def week_starts
      (@configuration.starts_on.beginning_of_week..@configuration.ends_on.beginning_of_week).step(7).to_a
    end

    def phase_for(date)
      @phases.find { |phase| phase.includes?(date) } || raise("No phase for #{date}")
    end

    def partial?(week_start)
      week_start < @configuration.starts_on || week_start + 6 > @configuration.ends_on
    end

    def recovery?(week_start)
      @recovery_flags.fetch(week_start)
    end

    def taper?(week_start)
      (week_start..week_start + 6).any? do |date|
        date.between?(@configuration.starts_on, @configuration.ends_on) && phase_for(date).kind == "taper"
      end
    end

    # Weeks whose load can anchor or be capped: full, hard, pre-taper weeks.
    def regular?(week_start)
      !(partial?(week_start) || recovery?(week_start) || taper?(week_start))
    end

    def weeks(prescriptions, warnings)
      week_starts.map do |week_start|
        items = prescriptions.select { |prescription| prescription.scheduled_on.between?(week_start, week_start + 6) }.sort_by(&:scheduled_on)
        phases = items.map(&:phase).uniq
        PreviewWeek.new(
          starts_on: week_start,
          ends_on: week_start + 6,
          phase: phases.one? ? phases.first : "mixed",
          recovery_week: recovery?(week_start),
          partial: partial?(week_start),
          prescriptions: items,
          duration_minutes: items.sum { |item| item.duration_minutes.to_i },
          estimated_tss: items.sum(&:estimated_tss),
          estimated_work_kj: items.sum { |item| item.metrics&.estimated_work_kj.to_f },
          warning: warnings.find { |warning| warning.include?(week_start.to_s) })
      end
    end
  end
end
