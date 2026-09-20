class HomeController < ApplicationController
  def index
    plan = TrainingPlan.active.first
    if plan
      Planning::HorizonMaterializer.new(plan).call
      @plan = TrainingPlan.includes(:target_event, :plan_phases, :time_off_periods, :adaptation_proposals).find(plan.id)
      @has_completed_workouts = @plan.planned_workouts.completed.exists?
    end

    @calendar = Planning::CalendarPresenter.new(@plan)
  end
end
