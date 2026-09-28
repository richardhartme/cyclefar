class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_one :rider_profile, dependent: :restrict_with_error
  has_many :training_plans, dependent: :restrict_with_error
  has_many :planned_workouts, through: :training_plans
  has_many :adaptation_proposals, through: :training_plans
  has_many :intervals_icu_syncs, dependent: :restrict_with_error

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :email_address, presence: true, uniqueness: { case_sensitive: false }
end
