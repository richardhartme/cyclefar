class AvailabilityChangesController < ApplicationController
  def new
    @plan = Current.user.training_plans.active.sole
    @effective_from = params[:effective_from].present? ? Date.iso8601(params[:effective_from]) : Date.current.clamp(@plan.starts_on, @plan.ends_on)
    unless @effective_from.between?(@plan.starts_on, @plan.ends_on)
      raise ArgumentError, "Choose a date within your plan"
    end
    @slots_by_weekday = Planning::AvailabilityForWeek.new(@plan, date: @effective_from).call
  rescue Date::Error, ArgumentError => error
    redirect_to new_availability_change_path, alert: error.message
  end

  def create
    plan = Current.user.training_plans.active.sole
    slots = params.fetch(:slots, {}).values.filter_map do |slot|
      slot.to_unsafe_h.symbolize_keys if ActiveModel::Type::Boolean.new.cast(slot[:enabled])
    end
    Planning::AvailabilityChanger.new(plan: plan, slots: slots, effective_from: Date.iso8601(params.require(:effective_from)), scope: params.require(:scope)).apply!
    redirect_to root_path, notice: "Availability updated."
  rescue Date::Error, ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to new_availability_change_path, alert: error.message
  end
end
