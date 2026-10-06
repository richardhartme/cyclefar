require "active_model"
require_relative "availability"
require_relative "rules"

module Planning
  # ActiveModel form object for plan creation with user inputs, parsing and validation.
  class PlanConfiguration
    include ActiveModel::Model

    attr_accessor :goal,
      :discipline,
      :starts_on,
      :duration_mode,
      :duration_months,
      :custom_duration_weeks,
      :ftp_watts,
      :include_base,
      :progression_mode,
      :hard_weeks_before_recovery,
      :event_name,
      :event_on,
      :event_discipline,
      :event_distance_km,
      :event_elevation_m,
      :event_expected_duration_minutes,
      :availability

    validates :goal, inclusion: { in: Training::Rules::GOALS }
    validates :discipline, inclusion: { in: Training::Rules::DISCIPLINES }
    validates :starts_on, :ftp_watts, :progression_mode, presence: true
    validates :ftp_watts, numericality: { only_integer: true, greater_than: 0 }
    validates :progression_mode, inclusion: { in: %w[continuous hard_recovery_cycle] }
    validates :duration_mode, inclusion: { in: %w[preset custom] }
    validate :duration_is_valid
    validate :event_is_valid
    validate :cycle_is_valid
    validate :availability_is_valid

    def initialize(attributes = {})
      super
      @goal = goal.to_s.presence
      @discipline = discipline.to_s.presence
      @starts_on = parse_date(starts_on)
      @duration_mode = duration_mode.presence || "preset"
      @duration_months = integer(duration_months || 3)
      @custom_duration_weeks = integer(custom_duration_weeks)
      @ftp_watts = integer(ftp_watts)
      @include_base = ActiveModel::Type::Boolean.new.cast(include_base)
      @progression_mode = progression_mode.presence || "continuous"
      @hard_weeks_before_recovery = integer(hard_weeks_before_recovery)
      @event_name = event_name.to_s.strip.presence
      @event_on = parse_date(event_on)
      @event_discipline = event_discipline.to_s.presence || @discipline
      @event_distance_km = decimal(event_distance_km)
      @event_elevation_m = integer(event_elevation_m)
      @event_expected_duration_minutes = integer(event_expected_duration_minutes)
      @invalid_availability = false
      @availability = normalize_availability(availability)
    end

    def event?
      goal == "event"
    end

    def ends_on
      return event_on if event?
      return unless starts_on

      duration_mode == "custom" ? starts_on + custom_duration_weeks.to_i.weeks - 1 : starts_on.advance(months: duration_months.to_i) - 1
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

    def event_is_valid
      return unless event?

      errors.add(:event_name, "is required") if event_name.blank?
      errors.add(:event_on, "is required") unless event_on
      errors.add(:event_discipline, "is invalid") unless Training::Rules::DISCIPLINES.include?(event_discipline)
      if starts_on && event_on && event_on < starts_on + Rules::MINIMUM_EVENT_LEAD_DAYS
        errors.add(:event_on, "must be at least four weeks after the plan start")
      end
      errors.add(:event_distance_km, "must be positive") if event_distance_km && event_distance_km <= 0
      errors.add(:event_elevation_m, "must be zero or greater") if event_elevation_m && event_elevation_m.negative?
      if event_expected_duration_minutes && event_expected_duration_minutes <= 0
        errors.add(:event_expected_duration_minutes, "must be positive")
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

    def parse_date(value)
      return value if value.is_a?(Date)
      return if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def integer(value)
      return value if value.is_a?(Integer)
      return if value.blank?

      Integer(value, exception: false)
    end

    def decimal(value)
      return if value.blank?

      Float(value, exception: false)
    end
  end
end
