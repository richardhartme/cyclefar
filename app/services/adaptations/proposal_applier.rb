module Adaptations
  # Accept or reject adaptation proposals; apply feedback or material change replans.
  class ProposalApplier
    def initialize(proposal)
      @proposal = proposal
    end

    def accept!
      TrainingPlan.transaction do
        @proposal.training_plan.lock!
        @proposal.lock!
        ProposalFreshness.new(@proposal).validate!
        case @proposal.payload["type"]
        when AdaptationProposal::MATERIAL_CHANGE_REPLAN
          apply_material_change_replan!
        when nil, "feedback"
          apply_feedback_adaptation!
        else
          raise ArgumentError, "Unsupported proposal type"
        end
        @proposal.destroy!
      end
    end

    def reject!
      @proposal.training_plan.with_lock do
        @proposal.lock!
        @proposal.destroy!
      end
    end

    private

    def apply_material_change_replan!
      Planning::MaterialChangeReplanner.new(@proposal).apply!
    end

    def apply_feedback_adaptation!
      comparison = ProposalComparison.new(@proposal).call
      comparison.changes.each do |change|
        Workouts::ManualEditor.new(change.workout).apply!(action: :adapt, progression_level: change.requested_level, lower_targets: change.lower_targets)
      end
      return if comparison.bias.delta.zero?

      state = @proposal.training_plan.progression_state.deep_dup
      key = "intensity_bias"
      state[key] = comparison.bias.after
      @proposal.training_plan.update!(progression_state: state)
    end
  end
end
