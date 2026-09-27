class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one :rider_profile, dependent: :restrict_with_error
  has_many :training_plans, dependent: :restrict_with_error

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
