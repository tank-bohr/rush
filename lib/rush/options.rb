# typed: true
# frozen_string_literal: true

module Rush
  # The shell options toggled by `set -[+]o name` / `set -[+]x` and friends
  # (:errexit, :nounset, :xtrace, :noglob, :verbose): the set of those currently
  # on, with #set to flip one and #on? to query it.
  class Options
    def initialize
      @enabled = Set.new
    end

    def set(name, enabled)
      enabled ? @enabled.add(name) : @enabled.delete(name)
    end

    def on?(name)
      @enabled.include?(name)
    end
  end
end
