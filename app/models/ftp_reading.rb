class FtpReading < ApplicationRecord
  belongs_to :rider_profile

  # A later entry wins when several readings share the same calendar date.
  scope :newest_first, -> { order(effective_on: :desc, id: :desc) }

  validates :ftp_watts, numericality: { only_integer: true, greater_than: 0 }
  validates :effective_on, presence: true
end
