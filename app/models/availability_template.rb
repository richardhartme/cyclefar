class AvailabilityTemplate < ApplicationRecord
  belongs_to :training_plan
  has_many :availability_slots, -> { order(:weekday) }, dependent: :destroy
  enum :source, %w[initial one_week_override from_date_change].index_by(&:itself), validate: true

  validates :effective_from, presence: true
  validates :effective_until, comparison: { greater_than_or_equal_to: :effective_from }, if: -> { effective_from && effective_until }
  validate :override_covers_calendar_week

  # Picks from templates the caller has already loaded, so date loops stay query-free.
  def self.for_date(templates, date)
    templates.select { |template| template.covers?(date) }
      .max_by { |template| [ template.one_week_override? ? 1 : 0, template.effective_from, template.id.to_i ] }
  end

  def covers?(date)
    effective_from <= date && (effective_until.nil? || effective_until >= date)
  end

  private

  def override_covers_calendar_week
    return unless one_week_override? && effective_from

    unless effective_from.monday? && effective_until == effective_from + 6
      errors.add(:base, "A one-week override must cover Monday through Sunday")
    end
  end
end
