module Workouts
  # One small object per manual edit; each answers the generation attributes
  # for the replacement definition.
  module EditActions
    def self.for(name)
      case name.to_s
      when "same" then Same
      when "shorter" then Shorter
      when "longer" then Longer
      when "change" then Change
      when "adapt" then Adapt
      else raise ArgumentError, "Unsupported workout action"
      end
    end
  end
end
