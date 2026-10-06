module Planning
  module V1
    class LoadContext
      def initialize(plan)
        @plan = plan
        @periods = plan.time_off_periods.to_a
        @recovery_flags = RecoverySchedule.new(
          starts_on: plan.starts_on,
          ends_on: plan.ends_on,
          phases: plan.plan_phases.sort_by(&:position),
          hard_weeks: plan.hard_recovery_cycle? ? plan.hard_weeks_before_recovery : nil).flags
      end

      def comparable_week?(week_start, workouts)
        return false if week_start < @plan.starts_on || week_start + 6 > @plan.ends_on
        return false if recovery_week?(week_start)
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
        # Saved tapered sets retain their normal intensity bands with reduced
        # hard time; legacy taper prescriptions retain the level-2 fallback.
        if workout.plan_phase&.kind_taper? && !workout.generation_context.fetch("load_adjustments", {}).key?("main_set_factor")
          maximum = [ maximum || 7, Rules::PHASE_LEVELS[:taper].end ].min
        end
        maximum
      end

      private

      def reduced?(workout)
        workout.plan_phase&.kind_taper? || recovery_week?(workout.scheduled_on.beginning_of_week) ||
          @periods.any? { |period| period.return_ramp_days && workout.scheduled_on.between?(period.ends_on + 1, period.ends_on + period.return_ramp_days) }
      end

      def recovery_week?(week_start)
        @recovery_flags.fetch(week_start, false)
      end
    end
  end
end
