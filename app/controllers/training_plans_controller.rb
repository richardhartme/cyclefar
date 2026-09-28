class TrainingPlansController < ApplicationController
  def new
    @configuration = Planning::PlanConfiguration.new(owned_plan_configuration || default_configuration)
  end

  def preview
    configuration = owned_plan_configuration
    unless configuration
      redirect_to new_training_plan_path, alert: "Preview the plan again before creating it."
      return
    end

    @configuration = Planning::PlanConfiguration.new(configuration)
    unless @configuration.valid?
      session.delete(:plan_configuration)
      redirect_to new_training_plan_path, alert: "Preview the plan again before creating it."
      return
    end

    @preview = Planning::PlanBuilder.new(@configuration).preview
    @presenter = Planning::PreviewPresenter.new(@preview)
  end

  def prepare_preview
    @configuration = Planning::PlanConfiguration.new(plan_configuration_params)
    if @configuration.valid?
      session[:plan_configuration] = { "user_id" => Current.user.id, "configuration" => plan_configuration_params }
      redirect_to preview_training_plan_path, status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def create
    configuration = owned_plan_configuration
    session.delete(:plan_configuration)
    @configuration = Planning::PlanConfiguration.new(configuration || {})
    unless @configuration.valid?
      flash[:alert] = "Preview the plan again before creating it."
      redirect_to new_training_plan_path
      return
    end

    Planning::PlanCreator.new(@configuration, user: Current.user).create!
    redirect_to root_path, notice: "Training plan created."
  rescue ActiveRecord::RecordInvalid => error
    flash[:alert] = error.record.errors.full_messages.to_sentence
    redirect_to new_training_plan_path
  end

  def destroy
    plan = Current.user.training_plans.active.sole
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

  def owned_plan_configuration
    draft = session[:plan_configuration]
    return unless draft

    if draft.is_a?(Hash) && draft["user_id"] == Current.user.id && draft["configuration"].is_a?(Hash)
      draft["configuration"]
    else
      session.delete(:plan_configuration)
      nil
    end
  end

  def default_configuration
    {
      goal: "general_fitness",
      discipline: "road",
      starts_on: Date.current,
      duration_mode: "preset",
      duration_months: 3,
      ftp_watts: Current.user.rider_profile&.ftp_watts,
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
