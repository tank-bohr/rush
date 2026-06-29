# typed: true
# frozen_string_literal: true

module Rush
  # Shell variables and the subset marked for export. The exported slice is what
  # external children receive (see SystemCalls#spawn).
  class Environment
    def initialize(source = ENV.to_h)
      @vars = source.dup
      @exported = source.keys.to_set
      @readonly = Set.new
    end

    def get(name)
      @vars[name]
    end

    def assign(name, value)
      raise ReadonlyError, "#{name}: is read only" if @readonly.include?(name)

      @vars[name] = value.to_s
    end

    def export(name)
      @exported.add(name)
    end

    def readonly(name)
      @readonly.add(name)
    end

    def unset(name)
      raise ReadonlyError, "#{name}: is read only" if @readonly.include?(name)

      @vars.delete(name)
      @exported.delete(name)
    end

    def exported
      # *@exported.to_a: splat needs an Array (Set splats via to_a at runtime, but
      # the checker won't); slice keeps @vars's own order, so this is unchanged.
      @vars.slice(*@exported.to_a)
    end
  end
end
