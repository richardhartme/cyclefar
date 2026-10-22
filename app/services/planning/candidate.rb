module Planning
  # A workout under consideration by the weekly load cap: its (re)generated
  # definition and metrics, or the stored workout when it is fixed.
  Candidate = Data.define(:workout, :definition, :metrics, :selected) do
    def initialize(workout:, definition: nil, metrics: nil, selected: true)
      super
    end

    def scheduled_on = workout.scheduled_on
    def progression_level = definition ? definition.progression_level : workout.progression_level
    def estimated_tss = metrics ? metrics.estimated_tss : workout.estimated_tss.to_f
    def adjustable? = selected && workout.workout?
    def reference_tss = selected ? estimated_tss : workout.generation_context.fetch("generated_tss", estimated_tss).to_f

    def reevaluate(definition, ftp_watts:)
      with(definition: definition, metrics: Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: ftp_watts).call)
    end
  end
end
