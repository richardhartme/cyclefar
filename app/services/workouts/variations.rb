require_relative "../training/v1/rules"

module Workouts
  module Variations
    def self.next_key(key)
      keys = Training::V1::Rules::VARIATION_KEYS
      index = keys.index(key.to_s)
      raise ArgumentError, "unknown variation key" unless index

      keys[(index + 1) % keys.length]
    end
  end
end
