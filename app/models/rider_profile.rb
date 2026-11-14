class RiderProfile < ApplicationRecord
  # Warn about a Garmin key expiring within this many days (GAR-002).
  GARMIN_KEY_EXPIRY_WARNING_DAYS = 14

  encrypts :intervals_icu_api_key
  encrypts :garmin_api_key
  belongs_to :user
  has_many :ftp_readings, dependent: :restrict_with_error

  validates :user_id, uniqueness: true
  validates :ftp_watts, numericality: { only_integer: true, greater_than: 0 }
  validates :garmin_api_key_expires_on, presence: true, if: -> { garmin_api_key.present? }
  validates :garmin_api_key, presence: true, on: :garmin_key

  # The FTP in force on a date: the newest reading on or before it, or the
  # earliest reading for a date before the first (FBK-004).
  def ftp_watts_on(date)
    reading = ftp_readings.where(effective_on: ..date).newest_first.first || ftp_readings.order(:effective_on, :id).first
    reading&.ftp_watts || ftp_watts
  end

  # nil without a key; otherwise :current, :expiring (14 days or fewer,
  # including the expiry day itself) or :expired once the date has passed.
  def garmin_api_key_expiry(today = Date.current)
    return if garmin_api_key.blank?
    return :expired if garmin_api_key_expires_on < today
    return :expiring if garmin_api_key_expires_on <= today + GARMIN_KEY_EXPIRY_WARNING_DAYS

    :current
  end
end
