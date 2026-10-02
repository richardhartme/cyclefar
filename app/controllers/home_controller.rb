class HomeController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    return render :welcome unless authenticated?

    plan = Current.user.training_plans.active.first
    if plan
      @load_warnings = Planning::HorizonMaterializer.new(plan).call
      @plan = Current.user.training_plans.includes(:target_event, :plan_phases, :time_off_periods, :adaptation_proposals).find(plan.id)
      @has_completed_workouts = @plan.planned_workouts.completed.exists?
      @proposal_comparisons = @plan.adaptation_proposals.to_h do |proposal|
        comparison = unless proposal.material_change_replan?
          begin
            Adaptations::ProposalComparison.new(proposal).call
          rescue ArgumentError
            nil
          end
        end
        [ proposal.id, comparison ]
      end
    end

    @calendar = Planning::CalendarPresenter.new(@plan)
  end
end
