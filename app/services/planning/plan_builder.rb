require_relative "../metrics/workout_calculator"
require_relative "../workouts/generator"
require_relative "../workouts/opener_generator"
require_relative "interval_selector"
require_relative "plan_configuration"
require_relative "phase_allocator"
require_relative "v1/rules"
require_relative "v1/weekly_load_cap"
require_relative "v1/load_reduction"
require_relative "v1/phase_progression"
require_relative "v1/recovery_schedule"
require_relative "v1/assessment_schedule"

module Planning
  # Builds a training plan preview with workouts, weeks, FTP tests and load enforcement.
  class PlanBuilder
    Prescription = Data.define(
      :scheduled_on,
      :kind,
      :intent,
      :subtype,
      :duration_minutes,
      :progression_level,
      :phase,
      :recovery_week,
      :name,
      :purpose,
      :main_set_summary,
      :metrics,
      :reason_codes,
      :definition) do
      def initialize(scheduled_on:, kind:, intent: nil, subtype: nil, duration_minutes: nil, progression_level: nil,
        phase:, recovery_week: false, name: nil, purpose: nil, main_set_summary: nil, metrics: nil, reason_codes: [], definition: nil)
        super(
          scheduled_on: scheduled_on,
          kind: kind.to_s.dup.freeze,
          intent: intent&.to_s&.dup&.freeze,
          subtype: subtype&.to_s&.dup&.freeze,
          duration_minutes: duration_minutes,
          progression_level: progression_level,
          phase: phase.to_s.dup.freeze,
          recovery_week: recovery_week,
          name: name&.dup&.freeze,
          purpose: purpose&.dup&.freeze,
          main_set_summary: main_set_summary&.dup&.freeze,
          metrics: metrics,
          reason_codes: reason_codes.map { |code| code.to_s.dup.freeze }.freeze,
          definition: definition)
      end

      def executable?
        %w[workout opener].include?(kind)
      end

      def estimated_tss = metrics&.estimated_tss.to_f
      def adjustable? = kind == "workout"

      def generation_context
        context = reason_codes.include?("weekly_load_cap") ? { "maximum_level" => progression_level } : {}
        context["maximum_level"] = progression_level if reason_codes.include?("taper_reduced_intensity")
        context["load_adjustments"] = definition.load_adjustments if definition && !definition.load_adjustments.empty?
        context
      end

      def intensity?
        %w[tempo sweet_spot threshold vo2_max over_under].include?(subtype)
      end
    end

    Week = Data.define(
      :starts_on,
      :ends_on,
      :phase,
      :recovery_week,
      :partial,
      :prescriptions,
      :duration_minutes,
      :estimated_tss,
      :estimated_work_kj,
      :warning) do
      def initialize(starts_on:, ends_on:, phase:, recovery_week:, partial:, prescriptions:, duration_minutes:, estimated_tss:, estimated_work_kj:, warning: nil)
        super(
          starts_on: starts_on,
          ends_on: ends_on,
          phase: phase.to_s.dup.freeze,
          recovery_week: recovery_week,
          partial: partial,
          prescriptions: prescriptions.freeze,
          duration_minutes: duration_minutes,
          estimated_tss: estimated_tss,
          estimated_work_kj: estimated_work_kj,
          warning: warning&.dup&.freeze)
      end
    end

    Preview = Data.define(:configuration, :starts_on, :ends_on, :phases, :prescriptions, :weeks, :ftp_test_dates, :warnings) do
      def initialize(configuration:, starts_on:, ends_on:, phases:, prescriptions:, weeks:, ftp_test_dates:, warnings:)
        super(
          configuration: configuration,
          starts_on: starts_on,
          ends_on: ends_on,
          phases: phases.freeze,
          prescriptions: prescriptions.freeze,
          weeks: weeks.freeze,
          ftp_test_dates: ftp_test_dates.freeze,
          warnings: warnings.map { |warning| warning.dup.freeze }.freeze)
      end
    end

    def initialize(configuration)
      @configuration = configuration
    end

    def preview
      raise ArgumentError, @configuration.errors.full_messages.to_sentence unless @configuration.valid?

      @phases = PhaseAllocator.new(@configuration).call
      @week_flags = recovery_week_flags
      prescriptions = build_prescriptions
      prescriptions = place_ftp_tests(prescriptions)
      evaluated = prescriptions.map { |prescription| evaluate(prescription) }
      evaluated, warnings = enforce_load_cap(evaluated)
      evaluated = taper_load(evaluated)
      weeks = build_weeks(evaluated, warnings)
      Preview.new(
        configuration: @configuration,
        starts_on: @configuration.starts_on,
        ends_on: @configuration.ends_on,
        phases: @phases,
        prescriptions: evaluated.sort_by(&:scheduled_on),
        weeks: weeks,
        ftp_test_dates: evaluated.select { |prescription| prescription.kind == "ftp_test" }.map(&:scheduled_on),
        warnings: warnings)
    end

    private

    def build_prescriptions
      interval_ordinals = Hash.new(0)
      opener_on = @configuration.event? ? @configuration.ends_on - 1 : nil
      prescriptions = []
      (@configuration.starts_on..@configuration.ends_on).each do |date|
        phase = phase_for(date)
        if @configuration.event? && date == @configuration.ends_on
          prescriptions << special(date, :event, phase, "Target event", "Your target event.")
          next
        end
        if date == opener_on
          prescriptions << opener(date, phase)
          next
        end
        slot = @configuration.slot_for(date.cwday)
        next unless slot

        recovery = recovery_week?(date)
        subtype, level, duration, reason_codes = normal_attributes(slot, phase, date, interval_ordinals, recovery)
        prescriptions << Prescription.new(
          scheduled_on: date,
          kind: :workout,
          intent: slot.intent,
          subtype: subtype,
          duration_minutes: duration,
          progression_level: level,
          phase: phase.kind,
          recovery_week: recovery,
          reason_codes: reason_codes)
      end
      prescriptions
    end

    def normal_attributes(slot, phase, date, interval_ordinals, recovery)
      if recovery
        subtype = slot.intent == "recovery" ? :recovery : :endurance
        return [ subtype, nil, reduced_duration(slot.duration_minutes, V1::Rules::RECOVERY_DURATION_FACTOR), [ "recovery_week_override" ] ]
      end
      if phase.kind == "taper"
        if slot.intensity? && taper_intensity?(date)
          subtype, level = planned_subtype_and_level(slot, taper_source_phase(phase), date, interval_ordinals)
          factor = early_long_taper?(date) ? V1::Rules::LONG_TAPER_DURATION_FACTOR : V1::Rules::TAPER_INTENSITY_DURATION_FACTOR
          return [ subtype, level, reduced_duration(slot.duration_minutes, factor), [ "taper_reduced_intensity" ] ]
        end
        factor = early_long_taper?(date) ? V1::Rules::LONG_TAPER_DURATION_FACTOR : V1::Rules::TAPER_DURATION_FACTOR
        return [ slot.intent == "recovery" ? :recovery : :endurance, nil, reduced_duration(slot.duration_minutes, factor), [ "taper_easy_override" ] ]
      end

      subtype, level = planned_subtype_and_level(slot, phase, date, interval_ordinals)
      [ subtype, level, slot.duration_minutes, [] ]
    end

    def planned_subtype_and_level(slot, phase, date, interval_ordinals)
      subtype = case slot.intent
      when "intervals"
        ordinal = interval_ordinals[phase.kind]
        interval_ordinals[phase.kind] += 1
        IntervalSelector.new(goal: @configuration.goal, discipline: @configuration.discipline, phase: phase.kind, ordinal: ordinal).call
      else
        slot.intent.to_sym
      end
      level = %i[tempo sweet_spot threshold vo2_max over_under].include?(subtype) ? level_for(date, phase) : nil
      [ subtype, level ]
    end

    def opener(date, phase)
      normal_duration = @configuration.slot_for(date.cwday)&.duration_minutes.to_i
      duration = normal_duration.between?(40, 45) ? normal_duration : normal_duration >= 45 ? 45 : 30
      Prescription.new(
        scheduled_on: date,
        kind: :opener,
        intent: :intervals,
        subtype: :endurance,
        duration_minutes: duration,
        phase: phase.kind,
        recovery_week: false,
        name: "Event Opener",
        purpose: "Brief activation before your event.",
        main_set_summary: "Short intensity touches with easy recovery",
        reason_codes: [ "event_opener" ])
    end

    def special(date, kind, phase, name, purpose)
      Prescription.new(scheduled_on: date, kind: kind, phase: phase.kind, name: name, purpose: purpose)
    end

    def phase_for(date)
      @phases.find { |phase| phase.includes?(date) } || raise("No phase for #{date}")
    end

    def taper_intensity?(date)
      taper = @phases.find { |phase| phase.kind == "taper" }
      return false if date >= @configuration.ends_on - V1::Rules::TAPER_NO_HARD_DAYS
      return true if early_long_taper?(date)

      start = [ taper.starts_on, @configuration.ends_on - V1::Rules::TAPER_FINAL_STAGE_DAYS + 1 ].max
      date == (start...@configuration.ends_on - V1::Rules::TAPER_NO_HARD_DAYS).find { |day| @configuration.slot_for(day.cwday)&.intensity? }
    end

    def early_long_taper?(date)
      taper = @phases.find { |phase| phase.kind == "taper" }
      taper && taper.ends_on - taper.starts_on + 1 >= V1::Rules::LONG_TAPER_MINIMUM_DAYS &&
        date.between?(taper.starts_on, @configuration.ends_on - V1::Rules::TAPER_FINAL_STAGE_DAYS)
    end

    def taper_source_phase(phase)
      return phase unless phase.kind == "taper"

      @phases[-2]
    end

    def reduced_duration(duration, factor)
      [ (duration * factor).round, Training::V1::Rules::MINIMUM_DURATION_MINUTES ].max
    end

    def recovery_week_flags
      V1::RecoverySchedule.new(
        starts_on: @configuration.starts_on,
        ends_on: @configuration.ends_on,
        phases: @phases,
        hard_weeks: @configuration.progression_mode == "hard_recovery_cycle" ? @configuration.hard_weeks_before_recovery : nil).flags
    end

    def recovery_week?(date)
      @week_flags.fetch(date.beginning_of_week)
    end

    def level_for(date, phase)
      V1::PhaseProgression.level(date: date, kind: phase.kind, starts_on: phase.starts_on, ends_on: phase.ends_on)
    end

    def place_ftp_tests(prescriptions)
      selected = V1::AssessmentSchedule.new(
        configuration: @configuration,
        phases: @phases,
        recovery_flags: @week_flags,
        prescriptions: prescriptions).dates
      prescriptions.map do |prescription|
        if selected.include?(prescription.scheduled_on)
          special(prescription.scheduled_on, :ftp_test, phase_for(prescription.scheduled_on), "FTP Test", "Perform your preferred FTP assessment, then update Settings.")
        else
          prescription
        end
      end
    end

    def evaluate(prescription)
      return prescription unless prescription.executable?

      definition = if prescription.kind == "opener"
        Workouts::OpenerGenerator.new(
          duration_minutes: prescription.duration_minutes,
          phase: prescription.phase,
          goal: @configuration.goal,
          discipline: @configuration.discipline).call
      else
        Workouts::Generator.new(
          subtype: prescription.subtype,
          duration_minutes: prescription.duration_minutes,
          progression_level: prescription.progression_level || 1,
          variation_key: Workouts::Variations.default_key(prescription.subtype),
          phase: prescription.phase,
          goal: @configuration.goal,
          discipline: @configuration.discipline,
          load_adjustments: prescription.reason_codes.include?("taper_reduced_intensity") ?
            { "main_set_factor" => early_long_taper?(prescription.scheduled_on) ? V1::Rules::LONG_TAPER_WORK_FACTOR : V1::Rules::TAPER_WORK_FACTOR } : {}).call
      end
      evaluated_definition(prescription, definition)
    end

    def evaluated_definition(prescription, definition)
      metrics = Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: @configuration.ftp_watts).call
      prescription.with(
        subtype: definition.subtype,
        progression_level: definition.progression_level,
        name: definition.name,
        purpose: definition.purpose,
        main_set_summary: definition.main_set_summary,
        metrics: metrics,
        definition: definition,
        reason_codes: (prescription.reason_codes + definition.reason_codes).uniq)
    end

    def taper_load(prescriptions)
      taper = @phases.find { |phase| phase.kind == "taper" }
      return prescriptions unless taper

      peak_items = prescriptions.group_by { |item| item.scheduled_on.beginning_of_week }.filter_map do |week_start, items|
        next if partial_week?(week_start) || recovery_week_start?(week_start) || taper_week?(week_start) || assessment_week?(items)

        items
      end.max_by { |items| tss_for(items) }
      return prescriptions unless peak_items

      peak = tss_for(peak_items)
      prescriptions = prescriptions.map do |item|
        next item unless item.phase == "taper" && item.intensity?

        reference = peak_items.find { |candidate| candidate.scheduled_on.cwday == item.scheduled_on.cwday && candidate.intensity? }
        reference ? evaluate(item.with(progression_level: reference.progression_level)) : item
      end

      prescriptions.group_by { |item| early_long_taper?(item.scheduled_on) }.each_value do |items|
        stage = items.select { |item| item.phase == "taper" }
        next if stage.empty?

        early = early_long_taper?(stage.first.scheduled_on)
        days = early ? @configuration.ends_on - V1::Rules::TAPER_FINAL_STAGE_DAYS - taper.starts_on + 1 : V1::Rules::TAPER_FINAL_STAGE_DAYS
        factor = early ? V1::Rules::LONG_TAPER_LOAD_FACTOR : V1::Rules::EVENT_WEEK_LOAD_FACTOR
        limit = peak * factor * days / 7.0
        # A sparse event week loses the event day's normal ride. Where possible,
        # retain enough easy volume to reach the stage target without adding days.
        while tss_for(stage) < limit
          candidate = stage.select do |item|
            item.kind == "workout" && !item.intensity? && item.duration_minutes < @configuration.slot_for(item.scheduled_on.cwday).duration_minutes
          end.max_by { |item| [ @configuration.slot_for(item.scheduled_on.cwday).duration_minutes - item.duration_minutes, -item.scheduled_on.jd ] }
          break unless candidate

          longer = evaluate(candidate.with(duration_minutes: candidate.duration_minutes + 1))
          break if longer.estimated_tss <= candidate.estimated_tss

          prescriptions[prescriptions.index(candidate)] = longer
          stage[stage.index(candidate)] = longer
        end
        # Volume is the adjustable taper input; opener and event remain fixed.
        while tss_for(stage) > limit
          candidate = stage.select { |item| item.kind == "workout" && item.duration_minutes > Training::V1::Rules::MINIMUM_DURATION_MINUTES }
            .max_by { |item| [ item.estimated_tss, -item.scheduled_on.jd ] }
          break unless candidate

          shortened = evaluate(candidate.with(duration_minutes: candidate.duration_minutes - 1))
          prescriptions[prescriptions.index(candidate)] = shortened
          stage[stage.index(candidate)] = shortened
        end
      end
      prescriptions
    end

    def enforce_load_cap(prescriptions)
      adjusted = prescriptions.dup
      warnings = []
      reference_tss = nil
      weekly_starts.each do |week_start|
        week_prescriptions = adjusted.select { |prescription| prescription.scheduled_on.between?(week_start, week_start + 6) }
        next if week_prescriptions.empty? || partial_week?(week_start) || recovery_week_start?(week_start) || taper_week?(week_start) || assessment_week?(week_prescriptions)

        current_tss = tss_for(week_prescriptions)
        if reference_tss && current_tss > reference_tss * (1 + V1::Rules::HARD_WEEK_GROWTH_CAP)
          adjusted = lower_week_load(adjusted, week_start, reference_tss * (1 + V1::Rules::HARD_WEEK_GROWTH_CAP))
          current_tss = tss_for(adjusted.select { |prescription| prescription.scheduled_on.between?(week_start, week_start + 6) })
          if current_tss > reference_tss * (1 + V1::Rules::HARD_WEEK_GROWTH_CAP)
            warnings << "Week of #{week_start}: your availability keeps projected load above the 8% growth target."
          end
        end
        reference_tss = current_tss
      end
      [ adjusted, warnings ]
    end

    def lower_week_load(prescriptions, week_start, cap)
      current = prescriptions.select { |item| item.scheduled_on.between?(week_start, week_start + 6) }
      reduced = V1::WeeklyLoadCap.reduce(current, limit: cap) do |candidate, stage|
        V1::LoadReduction.options(candidate.definition, stage: stage, intent: candidate.intent).map do |definition|
          evaluated_definition(candidate.with(reason_codes: (candidate.reason_codes + [ "weekly_load_cap" ]).uniq), definition)
        end
      end
      prescriptions.map { |item| (index = current.index(item)) ? reduced[index] : item }
    end

    def build_weeks(prescriptions, warnings)
      weekly_starts.map do |week_start|
        items = prescriptions.select { |prescription| prescription.scheduled_on.between?(week_start, week_start + 6) }.sort_by(&:scheduled_on)
        phases = items.map(&:phase).uniq
        Week.new(
          starts_on: week_start,
          ends_on: week_start + 6,
          phase: phases.one? ? phases.first : "mixed",
          recovery_week: recovery_week_start?(week_start),
          partial: partial_week?(week_start),
          prescriptions: items,
          duration_minutes: items.sum { |item| item.duration_minutes.to_i },
          estimated_tss: tss_for(items),
          estimated_work_kj: items.sum { |item| item.metrics&.estimated_work_kj.to_f },
          warning: warnings.find { |warning| warning.include?(week_start.to_s) })
      end
    end

    def weekly_starts
      (@configuration.starts_on.beginning_of_week..@configuration.ends_on.beginning_of_week).step(7).to_a
    end

    def tss_for(prescriptions)
      prescriptions.sum { |prescription| prescription.metrics&.estimated_tss.to_f }
    end

    def partial_week?(week_start)
      week_start < @configuration.starts_on || week_start + 6 > @configuration.ends_on
    end

    def recovery_week_start?(week_start)
      @week_flags.fetch(week_start)
    end

    def taper_week?(week_start)
      (week_start..week_start + 6).any? do |date|
        date.between?(@configuration.starts_on, @configuration.ends_on) && phase_for(date).kind == "taper"
      end
    end

    def assessment_week?(prescriptions)
      # An FTP test has no prescribed load, so its reduced total is not a
      # comparable hard-week reference for the automatic 8% growth rule.
      prescriptions.any? { |prescription| prescription.kind == "ftp_test" }
    end
  end
end
