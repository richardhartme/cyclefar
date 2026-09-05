class PlanPhase < ApplicationRecord
  belongs_to :training_plan
  has_many :planned_workouts, dependent: :restrict_with_error
  include WithinPlanDates

  enum :kind, %w[base build speciality taper].index_by(&:itself), prefix: true, validate: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :training_plan_id }
  validate :compatible_phase
  validate :ordered_contiguous_neighbours

  private

  def compatible_phase
    return unless training_plan

    errors.add(:kind, "requires Base to be included") if kind_base? && !training_plan.include_base?
    errors.add(:kind, "requires an event plan") if kind_taper? && !training_plan.event?
  end

  def ordered_contiguous_neighbours
    return unless training_plan && starts_on && ends_on && position

    siblings = training_plan.plan_phases.where.not(id: id)
    if siblings.where("starts_on <= ? AND ends_on >= ?", ends_on, starts_on).exists?
      errors.add(:base, "Phase dates must not overlap")
    end
    previous = siblings.find_by(position: position - 1)
    following = siblings.find_by(position: position + 1)
    if (position == 1 && starts_on != training_plan.starts_on) ||
        (previous && starts_on != previous.ends_on + 1) ||
        (following && ends_on + 1 != following.starts_on)
      errors.add(:base, "Phase dates must be contiguous in position order")
    end
  end
end
