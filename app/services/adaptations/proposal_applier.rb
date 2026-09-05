require_relative "../workouts/manual_editor"

module Adaptations
  class ProposalApplier
    def initialize(proposal)
      @proposal = proposal
    end

    def accept!
      TrainingPlan.transaction do
        @proposal.payload.fetch("changes", []).each do |change|
          workout = @proposal.training_plan.planned_workouts.find(change.fetch("planned_workout_id"))
          raise ArgumentError, "Proposal is stale" unless workout.planned? && workout.structured?

          Workouts::ManualEditor.new(workout).apply!(action: :adapt, progression_level: [ change.fetch("progression_level").to_i, 7 ].min)
        end
        bias = @proposal.payload.fetch("progression_bias", 0).to_i
        if bias.nonzero?
          state = @proposal.training_plan.progression_state.deep_dup
          key = "intensity_bias"
          state[key] = [ [ state.fetch(key, 0).to_i + bias, -2 ].max, 2 ].min
          @proposal.training_plan.update!(progression_state: state)
        end
        @proposal.destroy!
      end
    end

    def reject!
      @proposal.destroy!
    end
  end
end
