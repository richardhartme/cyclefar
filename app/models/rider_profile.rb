class RiderProfile < ApplicationRecord
  encrypts :intervals_icu_api_key
  belongs_to :user
  has_many :ftp_readings, dependent: :restrict_with_error

  validates :user_id, uniqueness: true
  validates :ftp_watts, numericality: { only_integer: true, greater_than: 0 }
end
