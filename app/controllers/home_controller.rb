class HomeController < ApplicationController
  def index
    @plan = TrainingPlan.active.includes(:target_event, :plan_phases, :time_off_periods, :adaptation_proposals, planned_workouts: :workout_steps).first
    return unless @plan

    Planning::HorizonMaterializer.new(@plan).call
    @plan.reload
    @calendar = Planning::CalendarPresenter.new(@plan)
  end
end
