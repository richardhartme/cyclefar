require_relative "../training/v1/rules"

module Workouts
  module Variations
    def self.random_key(subtype)
      subtype.to_s == "endurance" ? Training::V1::Rules::ENDURANCE_VARIATION_KEYS.sample : "a"
    end

    def self.next_key(key, subtype: nil)
      keys = subtype.to_s == "endurance" ? Training::V1::Rules::ENDURANCE_VARIATION_KEYS : Training::V1::Rules::VARIATION_KEYS
      index = keys.index(key.to_s)
      raise ArgumentError, "unknown variation key" unless index

      keys[(index + 1) % keys.length]
    end
  end
end
