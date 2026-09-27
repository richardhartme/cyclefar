class AdaptationProposalsController < ApplicationController
  before_action :load_proposal

  def accept
    Adaptations::ProposalApplier.new(@proposal).accept!
    redirect_to root_path, notice: "Adaptation applied."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to root_path, alert: error.message
  end

  def reject
    Adaptations::ProposalApplier.new(@proposal).reject!
    redirect_to root_path, notice: "Adaptation rejected."
  end

  private

  def load_proposal
    @proposal = Current.user.adaptation_proposals.find(params[:id])
  end
end
