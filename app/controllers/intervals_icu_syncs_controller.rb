class IntervalsIcuSyncsController < ApplicationController
  def create
    result = IntervalsIcu::SyncNextTwo.new(plan: TrainingPlan.active.sole).call
    redirect_to root_path, notice: "Synced #{result.synced_count} workout#{'s' unless result.synced_count == 1} to Intervals.icu."
  rescue IntervalsIcu::Client::Error, ActiveRecord::RecordInvalid => error
    redirect_to root_path, alert: error.message
  end
end
