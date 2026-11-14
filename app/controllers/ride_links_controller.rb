# Choose ride and Change ride for the Garmin rider: pick one of the rides
# near a completed workout, moving it from another workout if needed
# (GAR-008). Unlinking goes through RideFilesController#destroy.
class RideLinksController < ApplicationController
  include GarminRiderRequired

  before_action :load_workout

  def new
    @candidates = Activities::RideMatcher.new(Current.user).candidates(@workout)
  end

  def create
    activity = Current.user.activities.find(params.require(:activity_id))
    Activities::RideMatcher.new(Current.user).choose!(@workout, activity)
    redirect_to planned_workout_path(@workout), status: :see_other, notice: "Ride linked."
  rescue Activities::RideMatcher::Rejected, ActiveRecord::RecordInvalid => error
    redirect_to new_planned_workout_ride_link_path(@workout), status: :see_other, alert: error.message
  end

  private

  # Rides link only to completed history in the active plan.
  def load_workout
    @workout = Current.user.training_plans.active.sole.planned_workouts.completed.find(params[:planned_workout_id])
  end
end
