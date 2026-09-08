require_relative "../metrics/workout_calculator"
require_relative "../workouts/generator"
require_relative "../workouts/opener_generator"
require_relative "interval_selector"
require_relative "plan_configuration"
require_relative "phase_allocator"
require_relative "v1/rules"

module Planning
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
      :reason_codes) do
      def initialize(scheduled_on:, kind:, intent: nil, subtype: nil, duration_minutes: nil, progression_level: nil,
        phase:, recovery_week: false, name: nil, purpose: nil, main_set_summary: nil, metrics: nil, reason_codes: [])
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
          reason_codes: reason_codes.map { |code| code.to_s.dup.freeze }.freeze)
      end

      def executable?
        %w[workout opener].include?(kind)
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
      taper_intensity_on = first_taper_intensity_day
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
        subtype, level, duration, reason_codes = normal_attributes(slot, phase, date, interval_ordinals, recovery, taper_intensity_on)
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

    def normal_attributes(slot, phase, date, interval_ordinals, recovery, taper_intensity_on)
      if recovery
        subtype = slot.intent == "recovery" ? :recovery : :endurance
        return [ subtype, nil, reduced_duration(slot.duration_minutes, V1::Rules::RECOVERY_DURATION_FACTOR), [ "recovery_week_override" ] ]
      end
      if phase.kind == "taper"
        if slot.intensity? && date == taper_intensity_on
          subtype, level = planned_subtype_and_level(slot, taper_source_phase(phase), date, interval_ordinals)
          return [ subtype, [ level, 2 ].min, reduced_duration(slot.duration_minutes, 0.70), [ "taper_reduced_intensity" ] ]
        end
        return [ :endurance, nil, reduced_duration(slot.duration_minutes, V1::Rules::TAPER_DURATION_FACTOR), [ "taper_easy_override" ] ]
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

    def first_taper_intensity_day
      taper = @phases.find { |phase| phase.kind == "taper" }
      return unless taper

      (taper.starts_on...@configuration.ends_on).find do |date|
        @configuration.slot_for(date.cwday)&.intensity?
      end
    end

    def taper_source_phase(phase)
      return phase unless phase.kind == "taper"

      @phases[-2]
    end

    def reduced_duration(duration, factor)
      [ (duration * factor).round, Training::V1::Rules::MINIMUM_DURATION_MINUTES ].max
    end

    def recovery_week_flags
      starts = (@configuration.starts_on.beginning_of_week..@configuration.ends_on.beginning_of_week).step(7).to_a
      return starts.to_h { |start| [ start, false ] } if @configuration.progression_mode == "continuous"

      cycle_length = @configuration.hard_weeks_before_recovery + 1
      starts.each_with_index.to_h do |week_start, index|
        overlaps_taper = (week_start..week_start + 6).any? do |date|
          date.between?(@configuration.starts_on, @configuration.ends_on) && phase_for(date).kind == "taper"
        end
        [ week_start, !overlaps_taper && index % cycle_length == @configuration.hard_weeks_before_recovery ]
      end
    end

    def recovery_week?(date)
      @week_flags.fetch(date.beginning_of_week)
    end

    def level_for(date, phase)
      range = V1::Rules::PHASE_LEVELS.fetch(phase.kind.to_sym)
      fraction = (date - phase.starts_on).fdiv([ phase.ends_on - phase.starts_on, 1 ].max)
      [ range.begin + (fraction * range.size).floor, range.end ].min
    end

    def place_ftp_tests(prescriptions)
      return prescriptions if @configuration.ends_on - @configuration.starts_on + 1 < 42

      selected = []
      latest = @configuration.starts_on
      loop do
        lower = latest + V1::Rules::FTP_TEST_MIN_GAP_DAYS
        upper = [ latest + V1::Rules::FTP_TEST_MAX_GAP_DAYS, @configuration.ends_on - V1::Rules::FTP_TEST_EVENT_EXCLUSION_DAYS ].min
        candidates = prescriptions.select do |prescription|
          prescription.kind == "workout" && !prescription.recovery_week && prescription.scheduled_on.between?(lower, upper)
        end
        break if candidates.empty?

        desired = latest + V1::Rules::FTP_TEST_IDEAL_DAYS
        chosen = candidates.min_by do |prescription|
          preferred = prescription.intent == "intervals" ? 0 : 1
          [ preferred, (prescription.scheduled_on - desired).abs, prescription.scheduled_on ]
        end
        selected << chosen.scheduled_on
        latest = chosen.scheduled_on
      end
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
          variation_key: "a",
          phase: prescription.phase,
          goal: @configuration.goal,
          discipline: @configuration.discipline).call
      end
      metrics = Metrics::WorkoutCalculator.new(steps: definition.steps, ftp_watts: @configuration.ftp_watts).call
      prescription.with(
        subtype: definition.subtype,
        progression_level: definition.progression_level,
        name: definition.name,
        purpose: definition.purpose,
        main_set_summary: definition.main_set_summary,
        metrics: metrics,
        reason_codes: (prescription.reason_codes + definition.reason_codes).uniq)
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
      adjusted = prescriptions.dup
      loop do
        current = adjusted.select { |prescription| prescription.scheduled_on.between?(week_start, week_start + 6) }
        break adjusted if tss_for(current) <= cap

        candidate = current.select { |prescription| prescription.kind == "workout" && prescription.intensity? && prescription.progression_level.to_i > 1 }
          .max_by { |prescription| prescription.metrics.estimated_tss }
        break adjusted unless candidate

        replacement = evaluate(
          candidate.with(
            progression_level: candidate.progression_level - 1,
            reason_codes: (candidate.reason_codes + [ "weekly_load_cap" ]).uniq))
        adjusted[adjusted.index(candidate)] = replacement
      end
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
