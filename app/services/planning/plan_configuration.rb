require "active_model"

module Planning
  # ActiveModel form object for plan creation with user inputs, parsing and validation.
  class PlanConfiguration
    include ActiveModel::Model

    # Coercion that maps anything unparsable to nil, so validation can tell
    # "missing" from "malformed" using the raw input.
    class StrictInteger < ActiveModel::Type::Value
      def cast(value)
        return value if value.is_a?(Integer)
        return if value.blank?

        Integer(value, exception: false)
      end
    end

    class StrictDecimal < ActiveModel::Type::Value
      def cast(value)
        return if value.blank?

        Float(value, exception: false)
      end
    end

    class IsoDate < ActiveModel::Type::Value
      def cast(value)
        return value if value.is_a?(Date)
        return if value.blank?

        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end
    end

    class Text < ActiveModel::Type::Value
      def cast(value) = value.to_s.presence
    end

    class StrippedText < ActiveModel::Type::Value
      def cast(value) = value.to_s.strip.presence
    end

    include ActiveModel::Attributes

    attribute :goal, Text.new
    attribute :discipline, Text.new
    attribute :starts_on, IsoDate.new
    attribute :duration_mode, Text.new
    attribute :duration_months, StrictInteger.new
    attribute :custom_duration_weeks, StrictInteger.new
    attribute :ftp_watts, StrictInteger.new
    attribute :include_base, :boolean
    attribute :progression_mode, Text.new
    attribute :hard_weeks_before_recovery, StrictInteger.new
    attribute :event_name, StrippedText.new
    attribute :event_on, IsoDate.new
    attribute :event_discipline, Text.new
    attribute :event_distance_km, StrictDecimal.new
    attribute :event_elevation_m, StrictInteger.new
    attribute :event_expected_duration_minutes, StrictInteger.new
    attribute :event_details_open, :boolean

    # +plan_length+ is the form's single-select shorthand for duration mode and months.
    attr_accessor :plan_length, :availability

    validates :goal, inclusion: { in: Training::Rules::GOALS }
    validates :starts_on, :ftp_watts, :progression_mode, presence: true
    validates :ftp_watts, numericality: { only_integer: true, greater_than: 0 }
    validates :progression_mode, inclusion: { in: %w[continuous hard_recovery_cycle] }
    validates :duration_mode, inclusion: { in: %w[preset custom] }, unless: :event?
    validate :duration_is_valid, unless: :event?
    validate :event_is_valid
    validate :cycle_is_valid
    validate :availability_is_valid

    def initialize(attributes = {})
      @input_values = attributes.to_h.stringify_keys
      super
      self.duration_mode = "preset" if duration_mode.blank?
      self.duration_months = 3 if @input_values["duration_months"].nil?
      resolve_plan_length
      self.progression_mode = "continuous" if progression_mode.blank?
      self.hard_weeks_before_recovery = nil unless progression_mode == "hard_recovery_cycle"
      @invalid_availability = false
      @availability = normalize_availability(availability)
    end

    def event?
      goal == "event"
    end

    # Non-event discipline is a compatibility value, not a training choice (CYF-86).
    def training_discipline
      event? ? event_discipline : Rules::NON_EVENT_DISCIPLINE
    end

    def input_value(attribute)
      @input_values.fetch(attribute.to_s) { public_send(attribute) }
    end

    def ends_on
      return event_on if event?
      return unless starts_on

      duration_mode == "custom" ? custom_ends_on : preset_ends_on
    end

    def slot_for(weekday)
      availability.find { |slot| slot.weekday == weekday }
    end

    private

    def duration_is_valid
      if duration_mode == "preset"
        errors.add(:duration_months, "must be 1, 3 or 6 months") unless Rules::PRESET_MONTHS.include?(duration_months)
      elsif !custom_duration_weeks.is_a?(Integer) || custom_duration_weeks < Rules::MINIMUM_CUSTOM_WEEKS
        errors.add(:custom_duration_weeks, "must be at least #{Rules::MINIMUM_CUSTOM_WEEKS} whole weeks")
      end
    end

    def custom_ends_on
      return unless custom_duration_weeks.is_a?(Integer) && custom_duration_weeks >= Rules::MINIMUM_CUSTOM_WEEKS

      starts_on + custom_duration_weeks.weeks - 1
    end

    def preset_ends_on
      return unless duration_mode == "preset" && Rules::PRESET_MONTHS.include?(duration_months)

      starts_on.advance(months: duration_months) - 1
    end

    def resolve_plan_length
      if plan_length.present?
        self.duration_mode = plan_length == "custom" ? "custom" : "preset"
        self.duration_months = Integer(plan_length, exception: false) unless plan_length == "custom"
      end
      @plan_length = plan_length.presence || (duration_mode == "custom" ? "custom" : duration_months.to_s)
    end

    def event_is_valid
      return unless event?

      errors.add(:event_name, "is required") if event_name.blank?
      errors.add(:event_on, "is required") unless event_on
      errors.add(:event_discipline, "is invalid") unless Training::Rules::DISCIPLINES.include?(event_discipline)
      if starts_on && event_on && event_on < starts_on + Rules::MINIMUM_EVENT_LEAD_DAYS
        errors.add(:event_on, "must be at least four weeks after the plan start")
      end
      validate_optional_number(:event_distance_km, "must be positive", "must be a positive number") { |value| value <= 0 }
      validate_optional_number(:event_elevation_m, "must be zero or greater", "must be a whole number", &:negative?)
      validate_optional_number(:event_expected_duration_minutes, "must be positive", "must be a positive whole number") { |value| value <= 0 }
    end

    # +out_of_range+ is checked on a parsed value; +malformed+ applies when
    # something was entered that did not parse.
    def validate_optional_number(attribute, out_of_range, malformed)
      value = public_send(attribute)
      if value
        errors.add(attribute, out_of_range) if yield(value)
      elsif input_value(attribute).present?
        errors.add(attribute, malformed)
      end
    end

    def cycle_is_valid
      return unless progression_mode == "hard_recovery_cycle"

      unless hard_weeks_before_recovery.is_a?(Integer) && hard_weeks_before_recovery.positive?
        errors.add(:hard_weeks_before_recovery, "must be a positive whole number")
      end
    end

    def availability_is_valid
      errors.add(:availability, "contains an invalid training day") if @invalid_availability
      errors.add(:availability, "must include at least one training day") if availability.empty?
    end

    def normalize_availability(value)
      raw_slots = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
      raw_slots.values.filter_map do |attributes|
        values = attributes.respond_to?(:to_unsafe_h) ? attributes.to_unsafe_h : attributes.to_h
        next unless ActiveModel::Type::Boolean.new.cast(values["enabled"] || values[:enabled])

        Planning::Availability.new(
          weekday: integer(values["weekday"] || values[:weekday]),
          duration_minutes: integer(values["duration_minutes"] || values[:duration_minutes]),
          intent: values["intent"] || values[:intent])
      rescue ArgumentError
        @invalid_availability = true
        nil
      end.sort_by(&:weekday).freeze
    rescue NoMethodError
      [].freeze
    end

    def integer(value)
      StrictInteger.new.cast(value)
    end
  end
end
