module WithinPlanDates
  extend ActiveSupport::Concern

  included do
    validates :starts_on, :ends_on, presence: true
    validates :ends_on, comparison: { greater_than_or_equal_to: :starts_on }, if: -> { starts_on && ends_on }
    validate :dates_within_plan
  end

  private

  def dates_within_plan
    return unless training_plan&.starts_on && training_plan.ends_on && starts_on && ends_on

    unless starts_on >= training_plan.starts_on && ends_on <= training_plan.ends_on
      errors.add(:base, "Dates must be within the training plan")
    end
  end
end
