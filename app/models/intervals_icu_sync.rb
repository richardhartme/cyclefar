class IntervalsIcuSync < ApplicationRecord
  belongs_to :planned_workout, optional: true
  validates :planned_workout_id, uniqueness: true
  validates :external_id, presence: true, uniqueness: true, format: { with: /\Acyclefar-.+\z/ }
  validates :intervals_event_id, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :external_identity_is_stable, on: :update

  private

  def external_identity_is_stable
    if will_save_change_to_external_id? || will_save_change_to_planned_workout_id?
      errors.add(:base, "External workout identity cannot change")
    end
  end
end
