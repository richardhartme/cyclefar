class AvailabilityChangesController < ApplicationController
  def new
    @plan = TrainingPlan.active.sole
  end

  def create
    plan = TrainingPlan.active.sole
    slots = params.fetch(:slots, {}).values.filter_map do |slot|
      slot.to_unsafe_h.symbolize_keys if ActiveModel::Type::Boolean.new.cast(slot[:enabled])
    end
    Planning::AvailabilityChanger.new(plan: plan, slots: slots, effective_from: Date.iso8601(params.require(:effective_from)), scope: params.require(:scope)).apply!
    redirect_to root_path, notice: "Availability updated."
  rescue Date::Error, ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to new_availability_change_path, alert: error.message
  end
end
