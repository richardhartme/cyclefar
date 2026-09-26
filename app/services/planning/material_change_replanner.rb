module Planning
  class MaterialChangeReplanner
    def initialize(proposal)
      @proposal = proposal
      @plan = proposal.training_plan
    end

    def apply!
      source = @plan.planned_workouts.find(@proposal.source_workout_id)
      raise ArgumentError, "Proposal is stale" unless source.planned? && source.structured?

      dates_by_template.each do |template, dates|
        FuturePrescriber.new(plan: @plan, slots: template.availability_slots).replace!(
          dates,
          preserve_workout_ids: [ source.id ])
      end
    end

    private

    def dates_by_template
      templates = @plan.availability_templates.includes(:availability_slots).to_a
      proposal_range.to_a.group_by do |date|
        template = templates.select do |candidate|
          candidate.effective_from <= date && (candidate.effective_until.nil? || candidate.effective_until >= date)
        end.max_by { |candidate| [ candidate.one_week_override? ? 1 : 0, candidate.effective_from ] }
        raise ArgumentError, "No availability template applies on #{date.to_fs(:long)}" unless template

        template
      end
    end

    def proposal_range
      starts_on = Date.iso8601(@proposal.payload.fetch("starts_on"))
      ends_on = Date.iso8601(@proposal.payload.fetch("ends_on"))
      raise ArgumentError, "Proposal is stale" unless starts_on <= ends_on && starts_on >= Date.current && ends_on <= @plan.ends_on && (ends_on - starts_on).to_i <= 13

      starts_on..ends_on
    rescue Date::Error, KeyError
      raise ArgumentError, "Proposal is stale"
    end
  end
end
