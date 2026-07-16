# frozen_string_literal: true

# Sample statistics shared by the timing and allocation suites. Reports use
# the median because it is robust to one-off scheduler or GC noise in a way
# the mean is not.
module RushBench
  module_function

  def median(values)
    sorted = values.sort
    (sorted[(sorted.length - 1) / 2] + sorted[sorted.length / 2]) / 2.0
  end
end
