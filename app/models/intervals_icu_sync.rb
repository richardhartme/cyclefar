class IntervalsIcuSync < ApplicationRecord
  belongs_to :user
  belongs_to :planned_workout, optional: true
  validates :planned_workout_id, uniqueness: true, allow_nil: true
  validates :external_id, presence: true, uniqueness: true, format: { with: /\Acyclefar-.+\z/ }
  validates :intervals_event_id, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :planned_workout_belongs_to_user
  validate :external_identity_is_stable, on: :update

  private

  def external_identity_is_stable
    if will_save_change_to_external_id? || will_save_change_to_planned_workout_id? || will_save_change_to_user_id?
      errors.add(:base, "External workout identity cannot change")
    end
  end

  def planned_workout_belongs_to_user
    if planned_workout && planned_workout.training_plan.user_id != user_id
      errors.add(:planned_workout, "must belong to the sync owner")
    end
  end
end
