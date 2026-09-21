require_relative "../training/v1/rules"

module Workouts
  module Variations
    def self.keys_for(subtype)
      rules = Training::V1::Rules
      case subtype&.to_sym
      when :endurance then rules::ENDURANCE_VARIATION_KEYS
      when :recovery then rules::RECOVERY_VARIATION_KEYS
      when :opener then [ "activation" ]
      else rules::INTENSITY_VARIATION_KEYS
      end
    end

    def self.default_key(subtype)
      keys_for(subtype).first
    end

    def self.for_generation(subtype, current_key: nil)
      subtype = subtype&.to_sym
      subtype == :endurance ? keys_for(subtype).sample : current_key || default_key(subtype)
    end

    def self.next_key(key, subtype: nil)
      keys = keys_for(subtype)
      index = keys.index(key.to_s)
      raise ArgumentError, "unknown variation key" unless index

      keys[(index + 1) % keys.length]
    end
  end
end
