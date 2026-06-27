# frozen_string_literal: true

module Rush
  # Shell variables and the subset marked for export. The exported slice is what
  # external children receive (see SystemCalls#spawn).
  class Environment
    def initialize(source = ENV.to_h)
      @vars = source.dup
      @exported = source.keys.to_set
    end

    def get(name) = @vars[name]

    def assign(name, value) = @vars[name] = value.to_s

    def export(name) = @exported.add(name)

    def unset(name)
      @vars.delete(name)
      @exported.delete(name)
    end

    def exported = @vars.slice(*@exported)
  end
end
