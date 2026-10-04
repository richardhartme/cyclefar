require_relative "rules"

module Planning
  module V1
    class AssessmentSchedule
      def initialize(configuration:, phases:, recovery_flags:, prescriptions:)
        @configuration, @phases, @recovery_flags, @prescriptions = configuration, phases, recovery_flags, prescriptions
      end

      def dates
        return [] if @configuration.ends_on - @configuration.starts_on + 1 < Rules::FTP_TEST_MAX_GAP_DAYS

        eligible = @prescriptions.select { |item| eligible?(item) }
        selected = []
        latest = @configuration.starts_on
        loop do
          lower = latest + Rules::FTP_TEST_MIN_GAP_DAYS
          upper = latest + Rules::FTP_TEST_MAX_GAP_DAYS
          candidates = eligible.select { |item| item.scheduled_on.between?(lower, upper) }
          # If the whole window is unavailable, resume at the first valid slot.
          chosen = candidates.min_by { |item| [ rank(item, eligible), (item.scheduled_on - latest - Rules::FTP_TEST_IDEAL_DAYS).abs, item.scheduled_on ] }
          chosen ||= eligible.find { |item| item.scheduled_on > upper }
          break unless chosen

          selected << chosen.scheduled_on
          latest = chosen.scheduled_on
        end
        selected
      end

      private

      def eligible?(item)
        return false unless item.kind == "workout" && !item.recovery_week && item.phase != "taper"
        return false if @configuration.respond_to?(:assessment_blocked?) && @configuration.assessment_blocked?(item.scheduled_on)
        return false if @configuration.event? && (@configuration.ends_on - item.scheduled_on) <= Rules::FTP_TEST_EVENT_EXCLUSION_DAYS

        true
      end

      def rank(item, eligible)
        return 4 unless intensity?(item)

        week_start = item.scheduled_on.beginning_of_week
        first_in_week = eligible.find { |candidate| intensity?(candidate) && candidate.scheduled_on.between?(week_start, week_start + 6) }
        return 0 if @recovery_flags[week_start - 7] && item == first_in_week

        phase = @phases.find { |candidate| candidate.kind == item.phase }
        first_in_phase = eligible.find { |candidate| intensity?(candidate) && candidate.phase == item.phase }
        return 1 if %w[build speciality].include?(item.phase) && item == first_in_phase && item.scheduled_on < phase.starts_on + 7

        previous = @prescriptions.find { |candidate| candidate.scheduled_on == item.scheduled_on - 1 }
        return 2 if previous.nil? || previous.subtype == "recovery"

        3
      end

      def intensity?(item)
        %w[intervals tempo sweet_spot threshold vo2_max].include?(item.intent)
      end
    end
  end
end
