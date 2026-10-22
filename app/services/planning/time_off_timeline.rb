require_relative "return_ramp"

module Planning
  # The one place that decides which days a plan's time-off periods affect.
  # Periods are anything with id, starts_on, ends_on and return_ramp_days.
  class TimeOffTimeline
    def initialize(periods)
      @periods = periods.sort_by { |period| [ period.starts_on, period.id.to_i ] }
    end

    def break_on(date)
      @periods.find { |period| date.between?(period.starts_on, period.ends_on) }
    end

    def ramp_period_for(date)
      @periods.find { |period| ramp_covers?(period, date) }
    end

    def blocked?(date)
      !!(break_on(date) || ramp_period_for(date))
    end

    def latest_completed_before(date)
      @periods.select { |period| period.ends_on < date }.max_by(&:ends_on)
    end

    def overlaps_week?(week_start)
      periods_overlapping([ week_start ]).any?
    end

    def periods_overlapping(week_starts)
      @periods.select do |period|
        week_starts.any? { |week| period.starts_on <= week + 6 && period.ends_on + period.return_ramp_days.to_i >= week }
      end
    end

    # nil outside the period's ramp, so callers need no separate date test.
    def ramp_stage(period, date)
      return unless ramp_covers?(period, date)

      ReturnRamp.new(ends_on: period.ends_on, days: period.return_ramp_days).stage_on(date)
    end

    private

    def ramp_covers?(period, date)
      period.return_ramp_days.present? && date.between?(period.ends_on + 1, period.ends_on + period.return_ramp_days)
    end
  end
end
