require_relative "availability"
require_relative "existing_plan_configuration"
require_relative "horizon_materializer"
require_relative "plan_builder"

module Planning
  class FuturePrescriber
    attr_reader :slots

    def initialize(plan:, slots:)
      @plan = plan
      @slots = slots.map do |slot|
        attributes = slot.respond_to?(:weekday) ? { weekday: slot.weekday, duration_minutes: slot.duration_minutes, intent: slot.intent } : slot.symbolize_keys
        Availability.new(weekday: Integer(attributes[:weekday]), duration_minutes: Integer(attributes[:duration_minutes]), intent: attributes[:intent])
      end.sort_by(&:weekday).freeze
    end

    def replace!(range)
      dates = range.select { |date| date >= Date.current && date.between?(@plan.starts_on, @plan.ends_on) }
      return if dates.empty?

      @plan.planned_workouts.planned.where(kind: :workout, scheduled_on: dates).destroy_all
      prescriptions.select { |item| item.kind == "workout" && dates.include?(item.scheduled_on) }.each do |item|
        next if @plan.planned_workouts.where(scheduled_on: item.scheduled_on).exists?

        phase = @plan.plan_phases.find { |candidate| item.scheduled_on.between?(candidate.starts_on, candidate.ends_on) }
        @plan.planned_workouts.create!(plan_phase: phase, scheduled_on: item.scheduled_on, kind: item.kind, intent: item.intent,
          subtype: item.subtype, duration_minutes: item.duration_minutes, progression_level: item.progression_level,
          variation_key: "a", name: item.name, purpose: item.purpose, detail_status: :outline,
          estimated_np_watts: item.metrics&.estimated_np_watts, estimated_if: item.metrics&.estimated_if,
          estimated_tss: item.metrics&.estimated_tss, estimated_work_kj: item.metrics&.estimated_work_kj)
      end
      HorizonMaterializer.new(@plan).call
    end

    private

    def prescriptions
      PlanBuilder.new(ExistingPlanConfiguration.new(plan: @plan, availability: @slots)).preview.prescriptions
    end
  end
end
