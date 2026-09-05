class TrainingPlansController < ApplicationController
  def new
    @configuration = Planning::PlanConfiguration.new(default_configuration)
  end

  def preview
    @configuration = Planning::PlanConfiguration.new(plan_configuration_params)
    if @configuration.valid?
      @preview = Planning::PlanBuilder.new(@configuration).preview
      @presenter = Planning::PreviewPresenter.new(@preview)
    else
      render :new, status: :unprocessable_content
    end
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
    params.require(:plan_configuration).permit(:goal, :discipline, :starts_on, :duration_mode, :duration_months,
      :custom_duration_weeks, :ftp_watts, :include_base, :progression_mode, :hard_weeks_before_recovery, :event_name,
      :event_on, :event_discipline, :event_distance_km, :event_elevation_m, :event_expected_duration_minutes,
      availability: {}).to_h
  end
end
