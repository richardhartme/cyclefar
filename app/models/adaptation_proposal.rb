class AdaptationProposal < ApplicationRecord
  belongs_to :training_plan
  validates :reason, :expires_at, presence: true
  validate :payload_is_object

  private

  def payload_is_object
    errors.add(:payload, "must be an object") unless payload.is_a?(Hash)
  end
end
