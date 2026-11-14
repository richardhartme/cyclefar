# Garmin routes exist only for the GARMIN_RIDER_EMAIL rider; everyone else
# gets the same 404 as a missing record (GAR-001).
module GarminRiderRequired
  extend ActiveSupport::Concern

  included do
    before_action :require_garmin_rider
  end

  private

  def require_garmin_rider
    raise ActiveRecord::RecordNotFound unless Current.user.garmin_rider?
  end
end
