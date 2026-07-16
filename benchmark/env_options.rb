# frozen_string_literal: true

module RushBench
  # Numeric RUSH_BENCH_* environment options shared by the benchmark CLIs;
  # out-of-range or malformed values fail loudly instead of being clamped.
  module EnvOptions
    private

    def integer_env(name, default, valid)
      value = Integer(ENV.fetch(name, default.to_s), 10)
      return value if valid.cover?(value)

      raise ArgumentError, "#{name} is outside #{valid}"
    rescue ArgumentError
      raise ArgumentError, "#{name} must be an integer in #{valid}"
    end

    def float_env(name, default, minimum)
      value = Float(ENV.fetch(name, default.to_s))
      return value if value >= minimum

      raise ArgumentError, "#{name} must be at least #{minimum}"
    end
  end
end
