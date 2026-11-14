# Read-only detail of one of the rider's activities, opened from its
# calendar entry (GAR-010). Changing a link goes through the workout.
class ActivitiesController < ApplicationController
  def show
    @activity = Current.user.activities.includes(:planned_workout).find(params[:id])
  end
end
