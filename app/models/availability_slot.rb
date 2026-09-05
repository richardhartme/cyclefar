class AvailabilitySlot < ApplicationRecord
  INTENTS = %w[intervals endurance recovery vo2_max threshold sweet_spot tempo].freeze

  belongs_to :availability_template
  enum :intent, INTENTS.index_by(&:itself), prefix: true, validate: true

  # ISO Date#cwday: Monday=1, Sunday=7. Missing rows are rest days.
  validates :weekday, numericality: { only_integer: true, in: 1..7 }, uniqueness: { scope: :availability_template_id }
  validates :duration_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 30 }
end
