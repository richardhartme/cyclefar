module Planning
  # Reads the configured schedule, rather than recovery/taper-adjusted workouts.
  class AvailabilityForWeek
    def initialize(plan, date:)
      @plan = plan
      @date = date
    end

    def call
      templates = @plan.availability_templates.includes(:availability_slots).to_a
      (@date.beginning_of_week..@date.end_of_week).filter_map do |day|
        effective_on = day.clamp(@plan.starts_on, @plan.ends_on)
        template = templates.select do |candidate|
          candidate.effective_from <= effective_on && (candidate.effective_until.nil? || candidate.effective_until >= effective_on)
        end.max_by { |candidate| [ candidate.one_week_override? ? 1 : 0, candidate.effective_from, candidate.id ] }
        slot = template&.availability_slots&.find { |candidate| candidate.weekday == day.cwday }
        [ day.cwday, slot ] if slot
      end.to_h
    end
  end
end
