require_relative "step_sequence"

module Workouts
  class ProfileBuilder
    Segment = Data.define(:position, :label, :kind, :starts_at_seconds, :ends_at_seconds,
      :start_low_pct_ftp, :start_high_pct_ftp, :end_low_pct_ftp, :end_high_pct_ftp)
    Profile = Data.define(:duration_seconds, :segments)

    def initialize(steps:)
      @steps = StepSequence.normalize(steps)
    end

    def call
      elapsed = 0
      segments = @steps.map do |step|
        starts_at = elapsed
        elapsed += step.duration_seconds
        Segment.new(position: step.position, label: step.label, kind: step.kind,
          starts_at_seconds: starts_at, ends_at_seconds: elapsed,
          start_low_pct_ftp: step.target_low_pct_ftp, start_high_pct_ftp: step.target_high_pct_ftp,
          end_low_pct_ftp: step.end_target_low_pct_ftp || step.target_low_pct_ftp,
          end_high_pct_ftp: step.end_target_high_pct_ftp || step.target_high_pct_ftp)
      end
      Profile.new(duration_seconds: elapsed, segments: segments.freeze)
    end
  end
end
