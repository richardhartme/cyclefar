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

    def initialize(proposal)
      @proposal = proposal
      # Reload through ownership, avoiding associations cached by an earlier read.
      @plan = proposal.training_plan
    end

    def capture
      @plan.reload
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
      raise Unavailable, STALE_MESSAGE unless saved == { "version" => VERSION, "digest" => digest }
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
      PlanFingerprint.new(@proposal, plan: @plan, changes: (changes unless @proposal.material_change_replan?)).digest
    end

    # The proposal's workout changes, validated once.
    def changes
      @changes ||= @proposal.payload.fetch("changes", []).tap do |list|
        raise Unavailable, UNAVAILABLE_MESSAGE unless list.is_a?(Array) && list.all? { |change| change.is_a?(Hash) }
      end
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
        changes.each { |change| @plan.planned_workouts.find(change.fetch("planned_workout_id")) }
      end
    end
  end
end
