class TimeOffPeriodsController < ApplicationController
  def new
    @plan = Current.user.training_plans.active.sole
  end

  def create
    plan = Current.user.training_plans.active.sole
    Planning::TimeOffPlanner.new(plan: plan).add!(time_off_attributes)
    redirect_to root_path, notice: "Time off added."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to new_time_off_period_path, alert: error.message
  end

  def destroy
    period = TimeOffPeriod.find(params[:id])
    Planning::TimeOffPlanner.new(plan: Current.user.training_plans.active.sole).remove!(period)
    redirect_to root_path, notice: "Time off removed."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to root_path, alert: error.message
  end

  private

  def time_off_attributes
    params.require(:time_off_period).permit(:starts_on, :ends_on, :reason, :name, :return_ramp_days)
  end
end
