class TrainingPlansController < ApplicationController
  def new
    @configuration = Planning::PlanConfiguration.new(default_configuration)
  end

  def preview
    @configuration = Planning::PlanConfiguration.new(plan_configuration_params)
    if @configuration.valid?
      @preview = Planning::PlanBuilder.new(@configuration).preview
      @presenter = Planning::PreviewPresenter.new(@preview)
      session[:plan_configuration] = plan_configuration_params
    else
      render :new, status: :unprocessable_content
    end
  end

  def create
    @configuration = Planning::PlanConfiguration.new(session.delete(:plan_configuration) || {})
    unless @configuration.valid?
      flash[:alert] = "Preview the plan again before creating it."
      redirect_to new_training_plan_path
      return
    end

    Planning::PlanCreator.new(@configuration).create!
    redirect_to root_path, notice: "Training plan created."
  rescue ActiveRecord::RecordInvalid => error
    flash[:alert] = error.record.errors.full_messages.to_sentence
    redirect_to new_training_plan_path
  end

  def destroy
    plan = TrainingPlan.active.sole
    if plan.planned_workouts.completed.exists?
      TrainingPlan.transaction do
        plan.planned_workouts.planned.destroy_all
        plan.update!(status: :archived)
      end
      redirect_to root_path, notice: "Training plan archived. Completed workouts are kept as history."
    else
      plan.destroy!
      redirect_to root_path, notice: "Training plan deleted."
    end
  rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordInvalid => error
    redirect_to root_path, alert: error.message
  end

  private

  def default_configuration
    {
      goal: "general_fitness",
      discipline: "road",
      starts_on: Date.current,
      duration_mode: "preset",
      duration_months: 3,
      ftp_watts: RiderProfile.current.ftp_watts,
      include_base: true,
      progression_mode: "continuous",
      availability: {}
    }
  end

  def plan_configuration_params
    params.require(:plan_configuration).permit(
      :goal,
      :discipline,
      :starts_on,
      :duration_mode,
      :duration_months,
      :custom_duration_weeks,
      :ftp_watts,
      :include_base,
      :progression_mode,
      :hard_weeks_before_recovery,
      :event_name,
      :event_on,
      :event_discipline,
      :event_distance_km,
      :event_elevation_m,
      :event_expected_duration_minutes,
      availability: {}).to_h
  end
end
