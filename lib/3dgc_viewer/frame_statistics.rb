# frozen_string_literal: true

module ThreeDgcViewer
  class FrameStatistics
    DEFAULT_MAX_SAMPLES = 1_200

    def initialize(max_samples: DEFAULT_MAX_SAMPLES)
      @max_samples = positive_int(max_samples)
      @samples = []
    end

    def record(seconds)
      value = Float(seconds, exception: false)
      return false unless value&.finite? && value >= 0.0

      @samples << value
      overflow = @samples.length - @max_samples
      @samples.shift(overflow) if overflow.positive?
      true
    end

    def snapshot
      return nil if @samples.empty?

      sorted = @samples.sort
      {
        count: sorted.length,
        average_ms: to_ms(@samples.sum / @samples.length),
        p50_ms: percentile_ms(sorted, 50),
        p95_ms: percentile_ms(sorted, 95),
        p99_ms: percentile_ms(sorted, 99)
      }
    end

    def reset
      @samples.clear
    end

    private

    def positive_int(value)
      integer = value.to_i
      raise ArgumentError, "max_samples must be positive" unless integer.positive?

      integer
    end

    def percentile_ms(sorted, percentile)
      index = ((percentile / 100.0) * sorted.length).ceil - 1
      index = [[index, 0].max, sorted.length - 1].min
      to_ms(sorted[index])
    end

    def to_ms(seconds)
      seconds * 1000.0
    end
  end
end
