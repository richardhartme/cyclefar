module Planning
  module V1
    class LoadContext
      def initialize(plan)
        @plan = plan
        @periods = plan.time_off_periods.to_a
      end

      def comparable_week?(week_start, workouts)
        return false if week_start < @plan.starts_on || week_start + 6 > @plan.ends_on
        return false if recovery_week?(week_start) || workouts.any?(&:ftp_test?)
        return false if @plan.plan_phases.any? { |phase| phase.kind_taper? && phase.starts_on <= week_start + 6 && phase.ends_on >= week_start }

        @periods.none? do |period|
          period.starts_on <= week_start + 6 && period.ends_on + period.return_ramp_days.to_i >= week_start
        end
      end

      def maximum_level(workout)
        maximum = workout.generation_context["maximum_level"]
        if reduced?(workout)
          maximum = [ maximum || Training::V1::Rules::PROGRESSION_LEVELS.end, workout.progression_level || 1 ].min
        end
        maximum = [ maximum || 7, Rules::RECOVERY_MAXIMUM_LEVEL ].min if recovery_week?(workout.scheduled_on.beginning_of_week)
        maximum = [ maximum || 7, Rules::PHASE_LEVELS[:taper].end ].min if workout.plan_phase&.kind_taper?
        maximum
      end

      private

      def reduced?(workout)
        workout.plan_phase&.kind_taper? || recovery_week?(workout.scheduled_on.beginning_of_week) ||
          @periods.any? { |period| period.return_ramp_days && workout.scheduled_on.between?(period.ends_on + 1, period.ends_on + period.return_ramp_days) }
      end

      def recovery_week?(week_start)
        return false unless @plan.hard_recovery_cycle?

        index = ((week_start - @plan.starts_on.beginning_of_week) / 7).to_i
        index % (@plan.hard_weeks_before_recovery + 1) == @plan.hard_weeks_before_recovery
      end
    end
  end
end
