# The Garmin rider's Personal API key and its expiry date (GAR-002).
class GarminKeysController < ApplicationController
  include GarminRiderRequired

  before_action :load_profile

  def update
    attributes = garmin_key_params
    # A blank password field keeps the saved key; removal is its own action.
    attributes.delete(:garmin_api_key) if attributes[:garmin_api_key].blank?
    @profile.assign_attributes(attributes)

    if @profile.save(context: :garmin_key)
      redirect_to settings_path, notice: "Garmin key saved.", status: :see_other
    else
      # Redirect rather than re-render, so a submitted key never reaches a page.
      redirect_to settings_path, alert: "Garmin key not saved: #{@profile.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  def destroy
    @profile.update!(garmin_api_key: nil, garmin_api_key_expires_on: nil)
    redirect_to settings_path, notice: "Garmin key removed. Imported activities are kept.", status: :see_other
  end

  private

  def load_profile
    @profile = Current.user.rider_profile
    raise ActiveRecord::RecordNotFound unless @profile
  end

  def garmin_key_params
    params.expect(garmin_key: [ :garmin_api_key, :garmin_api_key_expires_on ])
  end
end
