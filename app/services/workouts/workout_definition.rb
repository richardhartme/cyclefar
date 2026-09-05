require_relative "step_sequence"

module Workouts
  WorkoutDefinition = Data.define(:engine_version, :subtype, :duration_minutes, :requested_progression_level,
    :progression_level, :variation_key, :phase, :goal, :discipline, :name, :purpose, :main_set_summary, :steps, :reason_codes) do
    def initialize(**attributes)
      attributes[:steps] = StepSequence.normalize(attributes.fetch(:steps))
      attributes[:reason_codes] = attributes.fetch(:reason_codes).map { |code| code.dup.freeze }.freeze
      attributes.transform_values! { |value| value.is_a?(String) ? value.dup.freeze : value }
      unless attributes[:steps].sum(&:duration_seconds) == attributes.fetch(:duration_minutes) * 60
        raise ArgumentError, "step durations must equal the requested workout duration"
      end
      super(**attributes)
    end
  end
end
