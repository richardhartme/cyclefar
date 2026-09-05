class PlannedWorkoutsController < ApplicationController
  before_action :load_workout

  def show
  end

  def shuffle
    result = Workouts::ManualEditor.new(@workout).apply!(action: params.require(:action_kind))
    redirect_to planned_workout_path(@workout), notice: result.material_change ? "Workout updated. This is a material change; the rest of the plan is unchanged." : "Workout updated."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to planned_workout_path(@workout), alert: error.message
  end

  def change
    result = Workouts::ManualEditor.new(@workout).apply!(action: :change, subtype: params.require(:subtype), duration_minutes: params.require(:duration_minutes))
    redirect_to planned_workout_path(@workout), notice: result.material_change ? "Workout changed. Replanning is optional and will be available in a later milestone." : "Workout changed."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to planned_workout_path(@workout), alert: error.message
  end

  def move
    raise ArgumentError, "Completed workouts cannot be moved" unless @workout.planned?

    destination = Date.iso8601(params.require(:scheduled_on))
    raise ArgumentError, "Choose an empty date inside this plan" unless destination.between?(@workout.training_plan.starts_on, @workout.training_plan.ends_on)
    raise ArgumentError, "That date already has a workout" if @workout.training_plan.planned_workouts.where(scheduled_on: destination).where.not(id: @workout.id).exists?

    phase = @workout.training_plan.plan_phases.find { |item| destination.between?(item.starts_on, item.ends_on) }
    @workout.update!(scheduled_on: destination, plan_phase: phase)
    redirect_to root_path, notice: "Workout moved to #{destination.to_fs(:long)}."
  rescue Date::Error, ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to planned_workout_path(@workout), alert: error.message
  end

  private

  def load_workout
    @workout = PlannedWorkout.includes(:workout_steps, :plan_phase, training_plan: :plan_phases).find(params[:id])
  end
end
