module Planning
  class ConfigurationSummaryPresenter
    def initialize(configuration)
      @configuration = configuration
      @configuration.valid?
    end

    def goal = PreviewPresenter::GOAL_LABELS.fetch(@configuration.goal, "Choose a goal")
    def start_date = @configuration.starts_on&.to_fs(:long) || "Choose a valid start date"

    def end_date
      return "Choose a valid start date and plan length" unless @configuration.event? || valid_non_event_dates?
      return "Choose a valid event date" if @configuration.event? && !valid_event_dates?

      @configuration.ends_on.to_fs(:long)
    end

    def plan_length
      return if @configuration.event?
      return "Choose a valid plan length" unless valid_non_event_dates?

      if @configuration.duration_mode == "custom"
        "#{@configuration.custom_duration_weeks} weeks"
      else
        "#{@configuration.duration_months} #{'month'.pluralize(@configuration.duration_months)}"
      end
    end

    def event_name = @configuration.event_name || "Add an event name"

    def discipline
      PreviewPresenter::DISCIPLINE_LABELS.fetch(@configuration.event_discipline, "Choose event discipline")
    end

    def training_days
      return "Choose valid training days" if @configuration.errors[:availability].any?

      count = @configuration.availability.size
      "#{count} training #{'day'.pluralize(count)}"
    end

    def normal_weekly_hours
      return "Choose valid training days" if @configuration.errors[:availability].any?

      minutes = @configuration.availability.sum(&:duration_minutes)
      hours, remainder = minutes.divmod(60)
      [ ("#{hours} h" if hours.positive?), ("#{remainder} min" if remainder.positive?) ].compact.join(" ")
    end

    def recovery_pattern
      case @configuration.progression_mode
      when "continuous" then "Continuous progression — no scheduled recovery weeks"
      when "hard_recovery_cycle"
        return "Choose a valid recovery pattern" if @configuration.errors[:hard_weeks_before_recovery].any?

        "#{@configuration.hard_weeks_before_recovery} hard weeks, then one recovery week"
      else "Choose a recovery pattern"
      end
    end

    private

    def valid_non_event_dates?
      @configuration.starts_on && @configuration.ends_on &&
        @configuration.errors[:duration_mode].empty? && @configuration.errors[:duration_months].empty? &&
        @configuration.errors[:custom_duration_weeks].empty?
    end

    def valid_event_dates?
      @configuration.starts_on && @configuration.ends_on && @configuration.errors[:event_on].empty?
    end
  end
end
