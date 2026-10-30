module Planning
  # Replans future workouts in response to a material change proposal, respecting availability.
  class MaterialChangeReplanner
    def initialize(proposal)
      @proposal = proposal
      @plan = proposal.training_plan
    end

    def validate!
      source = @plan.planned_workouts.find(@proposal.source_workout_id)
      raise ArgumentError, "Proposal is stale" unless source.planned? && source.structured?
      proposal_range
      source
    end

    def apply!
      source = validate!
      FuturePrescriber.replace_with_templates!(plan: @plan, dates: proposal_range, preserve_workout_ids: [ source.id ])
    end

    private

    def proposal_range
      starts_on = Date.iso8601(@proposal.payload.fetch("starts_on"))
      ends_on = Date.iso8601(@proposal.payload.fetch("ends_on"))
      raise ArgumentError, "Proposal is stale" unless starts_on <= ends_on && starts_on >= Date.current && ends_on <= @plan.ends_on && (ends_on - starts_on).to_i < Rules::PLANNING_HORIZON_DAYS

      starts_on..ends_on
    rescue Date::Error, KeyError
      raise ArgumentError, "Proposal is stale"
    end
  end
end
