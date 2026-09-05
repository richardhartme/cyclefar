class FtpReading < ApplicationRecord
  belongs_to :rider_profile

  validates :ftp_watts, numericality: { only_integer: true, greater_than: 0 }
  validates :effective_on, presence: true

  def readonly?
    persisted? || super
  end
end
