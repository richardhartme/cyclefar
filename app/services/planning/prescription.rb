module Planning
  Prescription = Data.define(
    :scheduled_on,
    :kind,
    :intent,
    :subtype,
    :duration_minutes,
    :progression_level,
    :phase,
    :recovery_week,
    :name,
    :purpose,
    :main_set_summary,
    :metrics,
    :reason_codes,
    :definition) do
    def initialize(scheduled_on:, kind:, intent: nil, subtype: nil, duration_minutes: nil, progression_level: nil,
      phase:, recovery_week: false, name: nil, purpose: nil, main_set_summary: nil, metrics: nil, reason_codes: [], definition: nil)
      super(
        scheduled_on: scheduled_on,
        kind: -kind.to_s,
        intent: intent && -intent.to_s,
        subtype: subtype && -subtype.to_s,
        duration_minutes: duration_minutes,
        progression_level: progression_level,
        phase: -phase.to_s,
        recovery_week: recovery_week,
        name: name && -name,
        purpose: purpose && -purpose,
        main_set_summary: main_set_summary && -main_set_summary,
        metrics: metrics,
        reason_codes: reason_codes.map { |code| -code.to_s }.freeze,
        definition: definition)
    end

    def executable?
      %w[workout opener].include?(kind)
    end

    def estimated_tss = metrics&.estimated_tss.to_f
    def adjustable? = kind == "workout"

    def generation_context
      context = reason_codes.include?("weekly_load_cap") ? { "maximum_level" => progression_level } : {}
      context["maximum_level"] = progression_level if reason_codes.include?("taper_reduced_intensity")
      context["load_adjustments"] = definition.load_adjustments if definition && !definition.load_adjustments.empty?
      context
    end

    def intensity?
      Training::Rules::INTENSITY_SUBTYPES.include?(subtype)
    end
  end
end
