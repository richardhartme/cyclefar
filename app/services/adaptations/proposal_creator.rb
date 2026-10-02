module Adaptations
  class ProposalCreator
    def initialize(plan)
      @plan = plan
    end

    def create!(reason:, payload:)
      @plan.with_lock do
        proposal = @plan.adaptation_proposals.build(reason: reason, payload: payload, created_at: Time.current, expires_at: 7.days.from_now)
        proposal.payload = payload.merge("freshness" => ProposalFreshness.new(proposal).capture)
        proposal.save!
        proposal
      end
    end
  end
end
