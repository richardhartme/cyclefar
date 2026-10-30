module Metrics
  # Calculates ridden metrics from FIT samples against the FTP frozen at
  # completion, using the same NP/IF/TSS conventions as planned estimates.
  class RideCalculator
    Result = Data.define(
      :started_at,
      :elapsed_seconds,
      :moving_seconds,
      :average_power_watts,
      :np_watts,
      :intensity_factor,
      :tss,
      :work_kj,
      :average_heart_rate_bpm)

    def initialize(samples:, ftp_watts:)
      raise ArgumentError, "Ride samples are required" if samples.empty?

      Workouts::StepDefinition.validate_ftp!(ftp_watts)
      @samples = samples
      @ftp_watts = ftp_watts
    end

    def call
      Result.new(
        started_at: @samples.first.recorded_at,
        elapsed_seconds: (@samples.last.recorded_at - @samples.first.recorded_at).round,
        moving_seconds: moving_seconds,
        average_heart_rate_bpm: average_heart_rate,
        **power_metrics)
    end

    private

    def moving_seconds
      @samples.each_cons(2).sum do |previous, sample|
        gap = (sample.recorded_at - previous.recorded_at).round
        moving = sample.speed_mps.nil? || sample.speed_mps >= Training::Rules::RIDE_MOVING_SPEED_MPS
        moving && gap <= Training::Rules::RIDE_PAUSE_GAP_SECONDS ? gap : 0
      end
    end

    def average_heart_rate
      rates = @samples.filter_map(&:heart_rate_bpm).reject(&:zero?)
      rates.sum.fdiv(rates.size) if rates.any?
    end

    # Power-meter recording is one sample per second; a dropout inside a
    # powered ride counts as zero watts, as head units do.
    def power_metrics
      return { average_power_watts: nil, np_watts: nil, intensity_factor: nil, tss: nil, work_kj: nil } if @samples.none?(&:power_watts)

      normalized_power = NormalizedPower.new
      power_sum = 0.0
      @samples.each do |sample|
        power = sample.power_watts.to_f
        normalized_power << power
        power_sum += power
      end
      intensity = normalized_power.watts / @ftp_watts
      {
        average_power_watts: power_sum / @samples.size,
        np_watts: normalized_power.watts,
        intensity_factor: intensity,
        tss: @samples.size / 3600.0 * intensity**2 * 100,
        work_kj: power_sum / 1000.0
      }
    end
  end
end
