module Adaptations
  class ProposalApplier
    def initialize(proposal)
      @proposal = proposal
    end

    def accept!
      TrainingPlan.transaction do
        @proposal.lock!
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
      @proposal.destroy!
    end

    private

    def apply_material_change_replan!
      Planning::MaterialChangeReplanner.new(@proposal).apply!
    end

    def apply_feedback_adaptation!
      @proposal.payload.fetch("changes", []).each do |change|
        workout = @proposal.training_plan.planned_workouts.find(change.fetch("planned_workout_id"))
        raise ArgumentError, "Proposal is stale" unless workout.planned? && workout.structured?

        Workouts::ManualEditor.new(workout).apply!(action: :adapt, progression_level: [ change.fetch("progression_level").to_i, 7 ].min)
      end
      bias = @proposal.payload.fetch("progression_bias", 0).to_i
      return unless bias.nonzero?

      state = @proposal.training_plan.progression_state.deep_dup
      key = "intensity_bias"
      state[key] = [ [ state.fetch(key, 0).to_i + bias, -2 ].max, 2 ].min
      @proposal.training_plan.update!(progression_state: state)
    end
  end
end
