module Workouts
  # Matches WorkoutStep attributes; watts and graph coordinates remain derived.
  StepDefinition = Data.define(
    :position,
    :kind,
    :label,
    :duration_seconds,
    :target_low_pct_ftp,
    :target_high_pct_ftp,
    :end_target_low_pct_ftp,
    :end_target_high_pct_ftp,
    :group_key,
    :group_iteration) do
    def initialize(position: 1, kind:, label:, duration_seconds:, target_low_pct_ftp:, target_high_pct_ftp:,
      end_target_low_pct_ftp: nil, end_target_high_pct_ftp: nil, group_key: nil, group_iteration: nil)
      raise ArgumentError, "position must be a positive integer" unless position.is_a?(Integer) && position.positive?
      raise ArgumentError, "duration_seconds must be a positive integer" unless duration_seconds.is_a?(Integer) && duration_seconds.positive?
      raise ArgumentError, "kind must be steady or ramp" unless %w[steady ramp].include?(kind.to_s)
      raise ArgumentError, "label must be present" unless label.is_a?(String) && !label.strip.empty?
      if group_iteration && !(group_iteration.is_a?(Integer) && group_iteration.positive?)
        raise ArgumentError, "group_iteration must be a positive integer"
      end
      validate_range!(target_low_pct_ftp, target_high_pct_ftp)
      if kind.to_s == "ramp"
        validate_range!(end_target_low_pct_ftp, end_target_high_pct_ftp)
      elsif end_target_low_pct_ftp || end_target_high_pct_ftp
        raise ArgumentError, "steady steps cannot have ramp endpoints"
      end
      super(
        position: position,
        kind: kind.to_s.dup.freeze,
        label: label.dup.freeze,
        duration_seconds: duration_seconds,
        target_low_pct_ftp: target_low_pct_ftp.to_f,
        target_high_pct_ftp: target_high_pct_ftp.to_f,
        end_target_low_pct_ftp: end_target_low_pct_ftp&.to_f,
        end_target_high_pct_ftp: end_target_high_pct_ftp&.to_f,
        group_key: group_key&.to_s&.dup&.freeze,
        group_iteration: group_iteration)
    end

    def self.from(step)
      return step if step.is_a?(self)

      attributes = if step.is_a?(Hash)
        step.transform_keys(&:to_sym).slice(*members)
      else
        members.to_h { |member| [ member, step.public_send(member) ] }
      end
      new(**attributes)
    end

    def self.validate_ftp!(ftp)
      raise ArgumentError, "FTP must be a positive integer" unless ftp.is_a?(Integer) && ftp.positive?
    end

    def representative_pct_at(second)
      unless second.is_a?(Integer) && second.between?(0, duration_seconds - 1)
        raise ArgumentError, "second must be a sample index inside the step"
      end
      start_pct = (target_low_pct_ftp + target_high_pct_ftp) / 2.0
      return start_pct if kind == "steady"

      end_pct = (end_target_low_pct_ftp + end_target_high_pct_ftp) / 2.0
      # Each sample represents the centre of its one-second interval. This
      # integrates linear ramps exactly, including the one-second edge case.
      start_pct + (end_pct - start_pct) * (second + 0.5) / duration_seconds
    end

    def target_watts(ftp_watts:)
      self.class.validate_ftp!(ftp_watts)
      {
        low_watts: (ftp_watts * target_low_pct_ftp / 100).round,
        high_watts: (ftp_watts * target_high_pct_ftp / 100).round,
        end_low_watts: end_target_low_pct_ftp && (ftp_watts * end_target_low_pct_ftp / 100).round,
        end_high_watts: end_target_high_pct_ftp && (ftp_watts * end_target_high_pct_ftp / 100).round
      }.freeze
    end

    private

    def validate_range!(low, high)
      unless [ low, high ].all? { |value| value.is_a?(Numeric) && value.real? && value.finite? && value.positive? } && low <= high
        raise ArgumentError, "FTP targets must be finite, positive, ordered ranges"
      end
    end
  end
end
