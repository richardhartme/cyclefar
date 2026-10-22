module Planning
  # Taper-stage decisions for an event plan: where intensity survives, how long
  # the early stage lasts and how much volume each stage may carry.
  class TaperPlan
    def initialize(configuration:, phases:)
      @configuration = configuration
      @phases = phases
    end

    def phase
      return @phase if defined?(@phase)

      @phase = @phases.find { |candidate| candidate.kind == "taper" }
    end

    def intensity_on?(date)
      return false if date >= @configuration.ends_on - Rules::TAPER_NO_HARD_DAYS
      return true if early_long?(date)

      start = [ phase.starts_on, @configuration.ends_on - Rules::TAPER_FINAL_STAGE_DAYS + 1 ].max
      date == (start...@configuration.ends_on - Rules::TAPER_NO_HARD_DAYS).find { |day| @configuration.slot_for(day.cwday)&.intensity? }
    end

    def early_long?(date)
      phase && phase.ends_on - phase.starts_on + 1 >= Rules::LONG_TAPER_MINIMUM_DAYS &&
        date.between?(phase.starts_on, @configuration.ends_on - Rules::TAPER_FINAL_STAGE_DAYS)
    end

    # Intensity inside the taper follows the phase that precedes it.
    def source_phase(current)
      current.kind == "taper" ? @phases[-2] : current
    end

    # Returns +prescriptions+ with each taper stage's volume steered towards its
    # share of +peak+ weekly TSS. +evaluate+ re-measures a changed prescription.
    def balance(prescriptions, peak:, &evaluate)
      balanced = prescriptions.group_by { |item| early_long?(item.scheduled_on) }.each_value.flat_map do |items|
        stage = items.select { |item| item.phase == "taper" }
        next [] if stage.empty?

        limit = peak * stage_load_factor(stage) * stage_days(stage) / 7.0
        stage = lengthen(stage, limit, &evaluate)
        shorten(stage, limit, &evaluate)
      end.index_by(&:scheduled_on)
      prescriptions.map { |item| balanced.fetch(item.scheduled_on, item) }
    end

    private

    def stage_load_factor(stage)
      early_long?(stage.first.scheduled_on) ? Rules::LONG_TAPER_LOAD_FACTOR : Rules::EVENT_WEEK_LOAD_FACTOR
    end

    def stage_days(stage)
      return Rules::TAPER_FINAL_STAGE_DAYS unless early_long?(stage.first.scheduled_on)

      @configuration.ends_on - Rules::TAPER_FINAL_STAGE_DAYS - phase.starts_on + 1
    end

    # A sparse event week loses the event day's normal ride. Where possible,
    # retain enough easy volume to reach the stage target without adding days.
    def lengthen(stage, limit, &evaluate)
      while tss_for(stage) < limit
        candidate = stage.select do |item|
          item.kind == "workout" && !item.intensity? && item.duration_minutes < slot_minutes(item)
        end.max_by { |item| [ slot_minutes(item) - item.duration_minutes, -item.scheduled_on.jd ] }
        return stage unless candidate

        longer = evaluate.call(candidate.with(duration_minutes: candidate.duration_minutes + 1))
        return stage if longer.estimated_tss <= candidate.estimated_tss

        stage = replace(stage, candidate, longer)
      end
      stage
    end

    # Volume is the adjustable taper input; opener and event remain fixed.
    def shorten(stage, limit, &evaluate)
      while tss_for(stage) > limit
        candidate = stage.select { |item| item.kind == "workout" && item.duration_minutes > Training::Rules::MINIMUM_DURATION_MINUTES }
          .max_by { |item| [ item.estimated_tss, -item.scheduled_on.jd ] }
        return stage unless candidate

        stage = replace(stage, candidate, evaluate.call(candidate.with(duration_minutes: candidate.duration_minutes - 1)))
      end
      stage
    end

    def replace(stage, candidate, replacement)
      stage.map { |item| item.equal?(candidate) ? replacement : item }
    end

    def slot_minutes(item)
      @configuration.slot_for(item.scheduled_on.cwday).duration_minutes
    end

    def tss_for(items)
      items.sum(&:estimated_tss)
    end
  end
end
