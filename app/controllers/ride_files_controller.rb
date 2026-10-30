class RideFilesController < ApplicationController
  before_action :load_workout

  def create
    activity = Workouts::RideFileAttacher.new(workout: @workout, file: params[:ride_file]).call
    notice = "Ride file added."
    notice += " It was ridden on #{activity.ridden_on.to_fs(:long)}, not the scheduled date." if activity.date_mismatch?
    redirect_to planned_workout_path(@workout), status: :see_other, notice: notice
  rescue Workouts::RideFileAttacher::Rejected, ActiveRecord::RecordInvalid => error
    redirect_to planned_workout_path(@workout), status: :see_other, alert: error.message
  end

  def destroy
    Workouts::RideFileRemover.new(@workout).call
    redirect_to planned_workout_path(@workout), status: :see_other, notice: "Ride file removed."
  end

  private

  # Ride files belong to completed history in the active plan only.
  def load_workout
    @workout = Current.user.training_plans.active.sole.planned_workouts.find(params[:planned_workout_id])
  end
end
