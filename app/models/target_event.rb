class TargetEvent < ApplicationRecord
  belongs_to :training_plan
  enum :discipline, TrainingPlan::DISCIPLINES.index_by(&:itself), validate: true

  validates :training_plan_id, uniqueness: true
  validates :name, :event_on, presence: true
  validates :distance_km, numericality: { greater_than: 0 }, allow_nil: true
  validates :elevation_m, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :expected_duration_minutes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :matches_event_plan
  validate :definition_is_immutable, on: :update

  private

  def matches_event_plan
    return unless training_plan

    errors.add(:training_plan, "must have an event goal") unless training_plan.event?
    errors.add(:event_on, "must match the plan end date") if event_on != training_plan.ends_on
  end

  def definition_is_immutable
    errors.add(:base, "Confirmed event definition cannot be changed") if has_changes_to_save?
  end
end
