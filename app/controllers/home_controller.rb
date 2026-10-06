class HomeController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    return render :welcome unless authenticated?

    plan = Current.user.training_plans.active.first
    if plan
      Planning::WorkoutBuilder.new(plan).call
      @load_warning_weeks = Planning::WeeklyLoadReview.new(plan).weeks_above_target
      @plan = Current.user.training_plans.includes(:target_event, :plan_phases, :time_off_periods, :adaptation_proposals).find(plan.id)
      @has_completed_workouts = @plan.planned_workouts.completed.exists?
      @proposal_errors = {}
      @proposal_comparisons = @plan.adaptation_proposals.to_h do |proposal|
        comparison = if proposal.material_change_replan?
          @proposal_errors[proposal.id] = Adaptations::ProposalFreshness.new(proposal).unavailability_message
          nil
        else
          begin
            Adaptations::ProposalComparison.new(proposal).call
          rescue ArgumentError => error
            @proposal_errors[proposal.id] = error.message
            nil
          end
        end
        [ proposal.id, comparison ]
      end
    end

    @calendar = Planning::CalendarPresenter.new(@plan)
  end
end
