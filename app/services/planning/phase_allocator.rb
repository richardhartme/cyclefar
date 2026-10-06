require_relative "rules"

module Planning
  # Allocates base, build, speciality and taper phases across the plan duration.
  class PhaseAllocator
    Phase = Data.define(:kind, :starts_on, :ends_on, :position) do
      def initialize(kind:, starts_on:, ends_on:, position:)
        raise ArgumentError, "phase dates must be ordered" unless starts_on.is_a?(Date) && ends_on.is_a?(Date) && ends_on >= starts_on

        super(kind: kind.to_s.dup.freeze, starts_on: starts_on, ends_on: ends_on, position: position)
      end

      def includes?(date)
        date.between?(starts_on, ends_on)
      end
    end

    def initialize(configuration)
      @configuration = configuration
    end

    def call
      taper_days = taper_days_for_plan
      pre_taper_end = @configuration.ends_on - taper_days
      kinds = @configuration.include_base ? %i[base build speciality] : %i[build speciality]
      lengths = allocate_lengths(kinds, pre_taper_end - @configuration.starts_on + 1)
      cursor = @configuration.starts_on
      phases = kinds.each_with_index.map do |kind, index|
        finish = cursor + lengths.fetch(kind) - 1
        phase = Phase.new(kind: kind, starts_on: cursor, ends_on: finish, position: index + 1)
        cursor = finish + 1
        phase
      end
      if taper_days.positive?
        phases << Phase.new(kind: :taper, starts_on: cursor, ends_on: @configuration.ends_on, position: phases.length + 1)
      end
      phases.freeze
    end

    private

    def taper_days_for_plan
      return 0 unless @configuration.event?

      preferred = @configuration.event_expected_duration_minutes.to_i > 300 ? 14 : 7
      phase_count = @configuration.include_base ? 3 : 2
      available_pre_taper_days = (@configuration.ends_on - @configuration.starts_on + 1) - preferred
      available_pre_taper_days >= phase_count * 7 ? preferred : 7
    end

    def allocate_lengths(kinds, total_days)
      raise ArgumentError, "Plan is too short to allocate each phase" if total_days < kinds.length * 7

      proportions = @configuration.include_base ? Rules::PHASE_PROPORTIONS[:with_base] : Rules::PHASE_PROPORTIONS[:without_base]
      remaining = total_days - kinds.length * 7
      exact = kinds.to_h { |kind| [ kind, remaining * proportions.fetch(kind) ] }
      lengths = kinds.to_h { |kind| [ kind, 7 + exact.fetch(kind).floor ] }
      leftovers = remaining - exact.values.sum(&:floor)
      kinds.sort_by { |kind| [ -(exact.fetch(kind) - exact.fetch(kind).floor), kinds.index(kind) ] }.first(leftovers).each { |kind| lengths[kind] += 1 }
      lengths
    end
  end
end
