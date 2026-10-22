module Planning
  class LoadContext
    def initialize(plan)
      @plan = plan
      @timeline = TimeOffTimeline.new(plan.time_off_periods.to_a)
      @recovery_flags = RecoverySchedule.for_plan(plan).flags
    end

    def comparable_week?(week_start, workouts)
      return false if week_start < @plan.starts_on || week_start + 6 > @plan.ends_on
      return false if recovery_week?(week_start)
      return false if @plan.plan_phases.any? { |phase| phase.kind_taper? && phase.starts_on <= week_start + 6 && phase.ends_on >= week_start }

      !@timeline.overlaps_week?(week_start)
    end

    def maximum_level(workout)
      maximum = workout.generation_context["maximum_level"]
      if reduced?(workout)
        maximum = [ maximum || Training::Rules::PROGRESSION_LEVELS.end, workout.progression_level || 1 ].min
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
        @timeline.ramp_period_for(workout.scheduled_on).present?
    end

    def recovery_week?(week_start)
      @recovery_flags.fetch(week_start, false)
    end
  end
end
