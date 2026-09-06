module Planning
  ExistingPlanConfiguration = Data.define(:plan, :availability) do
    def goal = plan.goal
    def discipline = plan.discipline
    def starts_on = plan.starts_on
    def ends_on = plan.ends_on
    def ftp_watts = plan.initial_ftp_watts
    def include_base = plan.include_base
    def progression_mode = plan.progression_mode
    def hard_weeks_before_recovery = plan.hard_weeks_before_recovery

    def event?
      plan.target_event.present?
    end

    def event_name = plan.target_event&.name
    def event_on = plan.target_event&.event_on
    def event_discipline = plan.target_event&.discipline
    def event_expected_duration_minutes = plan.target_event&.expected_duration_minutes

    def slot_for(weekday)
      availability.find { |slot| slot.weekday == weekday }
    end

    def valid? = true
    def errors = ActiveModel::Errors.new(self)
  end
end
