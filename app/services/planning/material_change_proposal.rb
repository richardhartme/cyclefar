module Planning
  # Creates or removes an adaptation proposal when a workout is materially changed.
  class MaterialChangeProposal
    def initialize(workout)
      @workout = workout
    end

    def replace!(material_change:)
      @workout.training_plan.with_lock do
        @workout.reload
        remove_existing!
        create_proposal! if material_change
      end
    end

    private

    def create_proposal!
      starts_on = [ Date.current, @workout.scheduled_on ].max
      Adaptations::ProposalCreator.new(@workout.training_plan).create!(
        reason: "This changes the load or intent of the day. Replan the next 14 days around it?",
        payload: {
          "type" => AdaptationProposal::MATERIAL_CHANGE_REPLAN,
          "source_workout_id" => @workout.id,
          "starts_on" => starts_on.iso8601,
          "ends_on" => [ starts_on + 13, @workout.training_plan.ends_on ].min.iso8601
        })
    end

    def remove_existing!
      @workout.training_plan.adaptation_proposals.select do |proposal|
        proposal.material_change_replan? && proposal.source_workout_id == @workout.id
      end.each(&:destroy!)
    end
  end
end
