class AvailabilityTemplate < ApplicationRecord
  belongs_to :training_plan
  has_many :availability_slots, -> { order(:weekday) }, dependent: :destroy
  enum :source, %w[initial one_week_override from_date_change].index_by(&:itself), validate: true

  validates :effective_from, presence: true
  validates :effective_until, comparison: { greater_than_or_equal_to: :effective_from }, if: -> { effective_from && effective_until }
  validate :override_covers_calendar_week

  private

  def override_covers_calendar_week
    return unless one_week_override? && effective_from

    unless effective_from.monday? && effective_until == effective_from + 6
      errors.add(:base, "A one-week override must cover Monday through Sunday")
    end
  end
end
