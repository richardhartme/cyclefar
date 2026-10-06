require_relative "rules"

module Planning
  module PhaseProgression
    def self.level(date:, kind:, starts_on:, ends_on:)
      range = Rules::PHASE_LEVELS.fetch(kind.to_sym)
      fraction = (date - starts_on).fdiv([ ends_on - starts_on, 1 ].max)
      (range.begin + (fraction * range.size).floor).clamp(range.begin, range.end)
    end
  end
end
