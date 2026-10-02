module Planning
  # Updates training availability and regenerates affected workouts.
  class AvailabilityChanger
    def initialize(plan:, slots:, effective_from:, scope:)
      @plan = plan
      @slots = slots
      @effective_from = effective_from
      @scope = scope.to_s
    end

    def apply!
      raise ArgumentError, "Choose at least one available training day" if @slots.empty?

      @plan.with_lock do
        template = create_template!
        re_prescribe!(affected_range)
        template
      end
    end

    private

    def create_template!
      case @scope
      when "one_week"
        start = @effective_from.beginning_of_week
        @plan.availability_templates.create!(effective_from: start, effective_until: start + 6, source: :one_week_override).tap { |template| create_slots!(template) }
      when "from_date"
        @plan.availability_templates.where(effective_until: nil).where("effective_from < ?", @effective_from).update_all(effective_until: @effective_from - 1)
        @plan.availability_templates.create!(effective_from: @effective_from, source: :from_date_change).tap { |template| create_slots!(template) }
      else
        raise ArgumentError, "Choose an availability-change scope"
      end
    end

    def create_slots!(template)
      normalized_slots.each { |slot| template.availability_slots.create!(weekday: slot.weekday, duration_minutes: slot.duration_minutes, intent: slot.intent) }
    end

    def affected_range
      @scope == "one_week" ? @effective_from.beginning_of_week..(@effective_from.beginning_of_week + 6) : @effective_from..@plan.ends_on
    end

    def re_prescribe!(range)
      FuturePrescriber.new(plan: @plan, slots: normalized_slots).replace!(range)
    end

    def normalized_slots
      @normalized_slots ||= FuturePrescriber.new(plan: @plan, slots: @slots).slots
    end
  end
end
