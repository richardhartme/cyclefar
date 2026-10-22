require "digest"

module Adaptations
  # Digest of the canonical plan inputs a proposal depends on. The caller supplies
  # a freshly loaded plan and the proposal's parsed changes.
  class PlanFingerprint
    WORKOUT_ATTRIBUTES = %w[id scheduled_on plan_phase_id kind intent subtype duration_minutes progression_level variation_key detail_status status generation_context].freeze

    def initialize(proposal, plan:, changes:)
      @proposal = proposal
      @plan = plan
      @changes = changes
    end

    def digest
      Digest::SHA256.hexdigest(canonical(context.as_json).to_json)
    end

    private

    def context
      @workouts = @plan.planned_workouts.includes(:workout_steps, :plan_phase).order(:scheduled_on, :id).to_a
      @periods = @plan.time_off_periods.order(:starts_on, :id).to_a
      @timeline = Planning::TimeOffTimeline.new(@periods)
      dates = affected_dates
      weeks = load_weeks(dates)
      relevant = @workouts.select { |workout| weeks.include?(workout.scheduled_on.beginning_of_week) }
      relevant |= @workouts.select { |workout| workout.id == @proposal.source_workout_id }
      breaks = applicable_breaks(dates)
      overlapping = @timeline.periods_overlapping(weeks)
      {
        plan: @plan.attributes.slice("id", "user_id", "status", *TrainingPlan::CONFIGURATION_ATTRIBUTES).except("initial_ftp_watts").merge("intensity_bias" => @plan.intensity_bias),
        proposal: @proposal.payload.except("freshness"),
        workouts: relevant.sort_by(&:id).map { |workout| workout_context(workout) },
        phases: @plan.plan_phases.where("starts_on <= ? AND ends_on >= ?", dates.max.end_of_week, weeks.min).map { |phase| phase.attributes.slice("id", "kind", "starts_on", "ends_on", "position") },
        availability: availability_context(dates),
        time_off: @periods.select { |period| breaks.include?(period) || overlapping.include?(period) }.map { |period| period.attributes.slice("id", "starts_on", "ends_on", "reason", "return_ramp_days") },
        pre_break_levels: breaks.map { |period| [ period.id, pre_break_level(period) ] },
        event: @proposal.material_change_replan? ? @plan.target_event&.attributes&.except("created_at", "updated_at") : nil
      }
    end

    def affected_dates
      if @proposal.material_change_replan?
        (Date.iso8601(@proposal.payload.fetch("starts_on"))..Date.iso8601(@proposal.payload.fetch("ends_on"))).to_a.tap do |dates|
          raise ProposalFreshness::Unavailable, ProposalFreshness::UNAVAILABLE_MESSAGE if dates.empty? || dates.size > Planning::Rules::PLANNING_HORIZON_DAYS
        end
      else
        ids = @changes.map { |change| Integer(change.fetch("planned_workout_id")) }
        dates = @workouts.select { |workout| ids.include?(workout.id) }.map(&:scheduled_on)
        # Bias-only/empty payloads still have a stable creation-time context.
        dates.presence || [ (@proposal.created_at || Time.current).to_date ]
      end
    end

    def load_weeks(dates)
      weeks = dates.map(&:beginning_of_week).uniq
      context = Planning::LoadContext.new(@plan)
      comparable = @workouts.group_by { |workout| workout.scheduled_on.beginning_of_week }.filter_map do |week, workouts|
        week if context.comparable_week?(week, workouts)
      end
      # The limiter uses the most recent comparable earlier week as its reference.
      (weeks + weeks.filter_map { |week| comparable.select { |candidate| candidate < week }.max }).uniq.sort
    end

    def availability_context(dates)
      templates = @plan.availability_templates.includes(:availability_slots).order(:id).to_a
      dates.sort.map do |date|
        template = AvailabilityTemplate.for_date(templates, date)
        { date: date, template_id: template&.id,
          slots: template&.availability_slots&.sort_by(&:weekday)&.map { |slot| slot.attributes.slice("weekday", "duration_minutes", "intent") } }
      end
    end

    def applicable_breaks(dates)
      return [] unless @proposal.material_change_replan?

      dates.filter_map { |date| @timeline.latest_completed_before(date) }.uniq.sort_by(&:id)
    end

    def pre_break_level(period)
      # Match re-prescription, including a new recent comparable baseline even
      # when an older, higher session is unchanged outside the affected weeks.
      Planning::PreBreakProgression.levels(@workouts, before: period.starts_on)
    end

    def workout_context(workout)
      workout.attributes.slice(*WORKOUT_ATTRIBUTES).merge(
        "steps" => workout.workout_steps.map { |step| Workouts::StepDefinition.from(step).to_h })
    end

    def canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end
  end
end
