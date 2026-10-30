module Metrics
  # Accumulates Normalized Power over a one-second power series. The first 29
  # samples use a growing window, then a rolling 30s window
  # (TRAINING_ENGINE.md section 25).
  class NormalizedPower
    def initialize
      @window = Array.new(Training::Rules::NP_WINDOW_SECONDS, 0.0)
      @window_sum = @fourth_power_sum = 0.0
      @count = 0
    end

    def <<(power)
      slot = @count % @window.size
      @window_sum += power - @window[slot]
      @window[slot] = power
      @count += 1
      @fourth_power_sum += (@window_sum / [ @count, @window.size ].min)**4
      self
    end

    def watts
      (@fourth_power_sum / @count)**0.25 unless @count.zero?
    end
  end
end
