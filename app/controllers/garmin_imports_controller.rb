# The rider-started Garmin Connect import (GAR-003), in the foreground request.
class GarminImportsController < ApplicationController
  include GarminRiderRequired

  def create
    result = GarminConnect::ImportActivities.new(user: Current.user).call
    redirect_to root_path, notice: "Imported #{result.imported_count}, updated #{result.updated_count}, removed #{result.removed_count}.", status: :see_other
  rescue GarminConnect::Client::Error, GarminConnect::ImportActivities::Rejected => error
    redirect_to root_path, alert: error.message, status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    # Activities saved before this one stay; a re-run is safe.
    redirect_to root_path, alert: "Garmin import stopped: #{error.record.errors.full_messages.to_sentence.presence || "an activity couldn't be saved"}.", status: :see_other
  end
end
