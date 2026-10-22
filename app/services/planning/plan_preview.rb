module Planning
  PlanPreview = Data.define(:configuration, :starts_on, :ends_on, :phases, :prescriptions, :weeks, :warnings) do
    def initialize(configuration:, starts_on:, ends_on:, phases:, prescriptions:, weeks:, warnings:)
      super(
        configuration: configuration,
        starts_on: starts_on,
        ends_on: ends_on,
        phases: phases.freeze,
        prescriptions: prescriptions.freeze,
        weeks: weeks.freeze,
        warnings: warnings.map { |warning| warning.dup.freeze }.freeze)
    end
  end
end
