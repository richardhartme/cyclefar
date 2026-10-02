require "digest"

module Adaptations
  # Fingerprint canonical inputs, rather than updated_at or derived FTP metrics.
  # All queries start at the proposal's plan; the digest stores no rider secrets.
  class ProposalFreshness
    VERSION = 1
    UNAVAILABLE_MESSAGE = "Proposal is unavailable. Reject it and review your upcoming workouts.".freeze
    EXPIRED_MESSAGE = "This proposal has expired. Dismiss it and review your upcoming workouts.".freeze
    STALE_MESSAGE = "Your plan has changed since this proposal was created. Dismiss it and review your upcoming workouts.".freeze
    LEGACY_MESSAGE = "This proposal can no longer be verified. Dismiss it and review your upcoming workouts.".freeze
    Unavailable = Class.new(ArgumentError)
    WORKOUT_ATTRIBUTES = %w[id scheduled_on plan_phase_id kind intent subtype duration_minutes progression_level variation_key detail_status status generation_context].freeze

    def initialize(proposal)
      @proposal = proposal
      # Reload through ownership, avoiding associations cached by an earlier read.
      @plan = proposal.training_plan
    end

    def capture
      { "version" => VERSION, "digest" => digest }
    rescue KeyError, TypeError, Date::Error
      raise Unavailable, UNAVAILABLE_MESSAGE
    end

    def validate!
      raise Unavailable, EXPIRED_MESSAGE if @proposal.expires_at && Time.current >= @proposal.expires_at
      raise Unavailable, UNAVAILABLE_MESSAGE unless @proposal.expires_at && @plan.reload.active?

      saved = @proposal.payload["freshness"]
      raise Unavailable, LEGACY_MESSAGE unless saved.is_a?(Hash) && saved["version"] == VERSION && saved["digest"].is_a?(String)
      validate_references!
      raise Unavailable, STALE_MESSAGE unless saved == capture
    rescue Unavailable
      raise
    rescue ActiveRecord::RecordNotFound, KeyError, TypeError, ArgumentError
      raise Unavailable, UNAVAILABLE_MESSAGE
    end

    def unavailability_message
      validate!
      nil
    rescue Unavailable => error
      error.message
    end

    private

    def digest
      Digest::SHA256.hexdigest(canonical(context.as_json).to_json)
    end

    def context
      @plan.reload
      @workouts = @plan.planned_workouts.includes(:workout_steps, :plan_phase).order(:scheduled_on, :id).to_a
      @periods = @plan.time_off_periods.order(:starts_on, :id).to_a
      dates = affected_dates
      weeks = load_weeks(dates)
      relevant = @workouts.select { |workout| weeks.include?(workout.scheduled_on.beginning_of_week) }
      relevant |= @workouts.select { |workout| workout.id == @proposal.source_workout_id }
      breaks = applicable_breaks(dates)
      {
        plan: @plan.attributes.slice("id", "user_id", "status", *TrainingPlan::CONFIGURATION_ATTRIBUTES).except("initial_ftp_watts").merge("intensity_bias" => @plan.progression_state.fetch("intensity_bias", 0).to_i),
        proposal: @proposal.payload.except("freshness"),
        workouts: relevant.sort_by(&:id).map { |workout| workout_context(workout) },
        phases: @plan.plan_phases.where("starts_on <= ? AND ends_on >= ?", dates.max.end_of_week, weeks.min).map { |phase| phase.attributes.slice("id", "kind", "starts_on", "ends_on", "position") },
        availability: availability_context(dates),
        time_off: @periods.select { |period| breaks.include?(period) || relevant_period?(period, weeks) }.map { |period| period.attributes.slice("id", "starts_on", "ends_on", "reason", "return_ramp_days") },
        pre_break_levels: breaks.map { |period| [ period.id, pre_break_level(period) ] },
        event: @proposal.material_change_replan? ? @plan.reload.target_event&.attributes&.except("created_at", "updated_at") : nil
      }
    end

    def affected_dates
      if @proposal.material_change_replan?
        (Date.iso8601(@proposal.payload.fetch("starts_on"))..Date.iso8601(@proposal.payload.fetch("ends_on"))).to_a.tap do |dates|
          raise Unavailable, UNAVAILABLE_MESSAGE if dates.empty? || dates.size > 14
        end
      else
        changes = @proposal.payload.fetch("changes", [])
        raise Unavailable, UNAVAILABLE_MESSAGE unless changes.is_a?(Array) && changes.all? { |change| change.is_a?(Hash) }

        ids = changes.map { |change| Integer(change.fetch("planned_workout_id")) }
        dates = @workouts.select { |workout| ids.include?(workout.id) }.map(&:scheduled_on)
        # Bias-only/empty payloads still have a stable creation-time context.
        dates.presence || [ (@proposal.created_at || Time.current).to_date ]
      end
    end

    def load_weeks(dates)
      weeks = dates.map(&:beginning_of_week).uniq
      context = Planning::V1::LoadContext.new(@plan)
      comparable = @workouts.group_by { |workout| workout.scheduled_on.beginning_of_week }.filter_map do |week, workouts|
        week if context.comparable_week?(week, workouts)
      end
      # The limiter uses the most recent comparable earlier week as its reference.
      (weeks + weeks.filter_map { |week| comparable.select { |candidate| candidate < week }.max }).uniq.sort
    end

    def availability_context(dates)
      templates = @plan.availability_templates.includes(:availability_slots).order(:id).to_a
      dates.sort.map do |date|
        template = templates.select do |candidate|
          candidate.effective_from <= date && (candidate.effective_until.nil? || candidate.effective_until >= date)
        end.max_by { |candidate| [ candidate.one_week_override? ? 1 : 0, candidate.effective_from ] }
        { date: date, template_id: template&.id,
          slots: template&.availability_slots&.sort_by(&:weekday)&.map { |slot| slot.attributes.slice("weekday", "duration_minutes", "intent") } }
      end
    end

    def relevant_period?(period, weeks)
      weeks.any? { |week| period.starts_on <= week + 6 && period.ends_on + period.return_ramp_days.to_i >= week }
    end

    def applicable_breaks(dates)
      return [] unless @proposal.material_change_replan?

      dates.filter_map { |date| @periods.select { |period| period.ends_on < date }.max_by(&:ends_on) }.uniq.sort_by(&:id)
    end

    def pre_break_level(period)
      # Match FuturePrescriber's baseline without fingerprinting unrelated old
      # rides whose edits do not change that maximum.
      @workouts.select { |workout| workout.scheduled_on < period.starts_on && workout.progression_level }.filter_map do |workout|
        workout.generation_context.fetch("generated_level", workout.progression_level)
      end.max || 1
    end

    def workout_context(workout)
      workout.attributes.slice(*WORKOUT_ATTRIBUTES).merge(
        "steps" => workout.workout_steps.map { |step| Workouts::StepDefinition.from(step).to_h })
    end

    def validate_references!
      if @proposal.payload.key?("source_workout_id")
        source = @plan.planned_workouts.find(@proposal.payload.fetch("source_workout_id"))
        expected = @proposal.material_change_replan? ? source.planned? && source.structured? : source.completed?
        raise Unavailable, UNAVAILABLE_MESSAGE unless expected
      end
      if @proposal.material_change_replan?
        Planning::MaterialChangeReplanner.new(@proposal).validate!
      elsif ![ nil, "feedback" ].include?(@proposal.payload["type"])
        raise Unavailable, UNAVAILABLE_MESSAGE
      else
        changes = @proposal.payload.fetch("changes", [])
        raise Unavailable, UNAVAILABLE_MESSAGE unless changes.is_a?(Array) && changes.all? { |change| change.is_a?(Hash) }

        changes.each { |change| @plan.planned_workouts.find(change.fetch("planned_workout_id")) }
      end
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
