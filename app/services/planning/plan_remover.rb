module Planning
  class PlanRemover
    def initialize(plan)
      @plan = plan
    end

    def call
      IntervalsIcu::Synchronization.with_owner_lock(@plan.user) do
        @plan.with_lock do
          IntervalsIcu::RemovePlanEvents.new(@plan).call
          if @plan.planned_workouts.completed.exists?
            @plan.planned_workouts.planned.each(&:destroy!)
            @plan.update!(status: :archived)
            true
          else
            @plan.destroy!
            false
          end
        end
      end
    end
  end
end
