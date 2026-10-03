module Planning
  # Creates a new TrainingPlan record and all associated phases, workouts and event.
  class PlanCreator
    def initialize(configuration, user:)
      @configuration = configuration
      @user = user
    end

    def create!
      preview = PlanBuilder.new(@configuration).preview
      TrainingPlan.transaction do
        plan = TrainingPlan.create!(
          user: @user,
          goal: @configuration.goal,
          discipline: @configuration.discipline,
          starts_on: preview.starts_on,
          ends_on: preview.ends_on,
          include_base: @configuration.include_base,
          progression_mode: @configuration.progression_mode,
          hard_weeks_before_recovery: @configuration.hard_weeks_before_recovery,
          initial_ftp_watts: @configuration.ftp_watts,
          progression_state: {},
          engine_version: Training::V1::Rules::ENGINE_VERSION)
        phases = preview.phases.to_h { |phase| [ phase.position, plan.plan_phases.create!(kind: phase.kind, starts_on: phase.starts_on, ends_on: phase.ends_on, position: phase.position) ] }
        template = plan.availability_templates.create!(effective_from: plan.starts_on, source: :initial)
        @configuration.availability.each { |slot| template.availability_slots.create!(weekday: slot.weekday, duration_minutes: slot.duration_minutes, intent: slot.intent) }
        if @configuration.event?
          plan.create_target_event!(
            name: @configuration.event_name,
            event_on: @configuration.event_on,
            discipline: @configuration.event_discipline,
            distance_km: @configuration.event_distance_km,
            elevation_m: @configuration.event_elevation_m,
            expected_duration_minutes: @configuration.event_expected_duration_minutes)
        end
        preview.prescriptions.each do |item|
          next if item.kind == "event"
          phase = phases.values.find { |candidate| item.scheduled_on.between?(candidate.starts_on, candidate.ends_on) }
          plan.planned_workouts.create!(
            plan_phase: phase,
            scheduled_on: item.scheduled_on,
            kind: item.kind,
            intent: item.intent,
            subtype: item.subtype,
            duration_minutes: item.duration_minutes,
            progression_level: item.progression_level,
            generation_context: item.generation_context,
            variation_key: item.definition&.variation_key,
            name: item.name,
            purpose: item.purpose,
            detail_status: :outline,
            estimated_np_watts: item.metrics&.estimated_np_watts,
            estimated_if: item.metrics&.estimated_if,
            estimated_tss: item.metrics&.estimated_tss,
            estimated_work_kj: item.metrics&.estimated_work_kj)
        end
        HorizonMaterializer.new(plan).call
        plan
      end
    end
  end
end
