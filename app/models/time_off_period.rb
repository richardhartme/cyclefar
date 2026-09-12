class TimeOffPeriod < ApplicationRecord
  belongs_to :training_plan
  include WithinPlanDates
  enum :reason, %w[holiday illness recovery event other].index_by(&:itself), validate: true

  validates :return_ramp_days, numericality: { only_integer: true, greater_than: 0 }, if: :return_ramp_required?
  validates :return_ramp_days, absence: true, unless: :return_ramp_required?
  validate :no_overlapping_periods

  private

  def return_ramp_required?
    illness? || recovery?
  end

  def no_overlapping_periods
    return unless training_plan && starts_on && ends_on

    if training_plan.time_off_periods.where.not(id: id).where("starts_on <= ? AND ends_on >= ?", ends_on, starts_on).exists?
      errors.add(:base, "Time off must not overlap another period")
    end
  end
end
