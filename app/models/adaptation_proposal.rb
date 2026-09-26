class AdaptationProposal < ApplicationRecord
  MATERIAL_CHANGE_REPLAN = "material_change_replan".freeze

  belongs_to :training_plan
  validates :reason, :expires_at, presence: true
  validate :payload_is_object

  def material_change_replan?
    payload["type"] == MATERIAL_CHANGE_REPLAN
  end

  def source_workout_id
    payload["source_workout_id"]&.to_i
  end

  private

  def payload_is_object
    errors.add(:payload, "must be an object") unless payload.is_a?(Hash)
  end
end
