class RiderProfile < ApplicationRecord
  encrypts :intervals_icu_api_key
  has_many :ftp_readings, dependent: :restrict_with_error

  attribute :id, :integer, default: 1
  validates :id, inclusion: { in: [ 1 ] }, uniqueness: true
  validates :ftp_watts, numericality: { only_integer: true, greater_than: 0 }

  # An unsaved profile lets first-run Settings ask for FTP without inventing one.
  def self.current
    find_by(id: 1) || new
  end
end
