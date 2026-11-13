class RiderProfile < ApplicationRecord
  encrypts :intervals_icu_api_key
  belongs_to :user
  has_many :ftp_readings, dependent: :restrict_with_error

  validates :user_id, uniqueness: true
  validates :ftp_watts, numericality: { only_integer: true, greater_than: 0 }

  # The FTP in force on a date: the newest reading on or before it, or the
  # earliest reading for a date before the first (FBK-004).
  def ftp_watts_on(date)
    reading = ftp_readings.where(effective_on: ..date).newest_first.first || ftp_readings.order(:effective_on, :id).first
    reading&.ftp_watts || ftp_watts
  end
end
