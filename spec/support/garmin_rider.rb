# GARMIN_RIDER_EMAIL names the one rider who may use Garmin (GAR-001). Every
# example starts with it unset, whatever the developer's shell holds.
module GarminRider
  def with_garmin_rider_email(email)
    original = ENV["GARMIN_RIDER_EMAIL"]
    ENV["GARMIN_RIDER_EMAIL"] = email
    yield
  ensure
    ENV["GARMIN_RIDER_EMAIL"] = original
  end
end

RSpec.configure do |config|
  config.include GarminRider
  config.around { |example| with_garmin_rider_email(nil) { example.run } }
end
