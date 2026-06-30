# typed: true
# frozen_string_literal: true

module Rush
  # The shell options toggled by `set -[+]o name` / `set -[+]x` and friends
  # (:errexit, :nounset, :xtrace, :noglob, :verbose): the set of those currently
  # on, with #set to flip one and #on? to query it.
  class Options
    extend T::Sig

    sig { void }
    def initialize
      @enabled = Set.new
    end

    sig { params(name: Symbol, enabled: T::Boolean).void }
    def set(name, enabled)
      enabled ? @enabled.add(name) : @enabled.delete(name)
    end

    sig { params(name: Symbol).returns(T::Boolean) }
    def on?(name)
      @enabled.include?(name)
    end
  end
end
