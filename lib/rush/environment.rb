# typed: true
# frozen_string_literal: true

module Rush
  # Shell variables and the subset marked for export. The exported slice is what
  # external children receive (see SystemCalls#spawn).
  class Environment
    extend T::Sig

    sig { params(source: T::Hash[String, String]).void }
    def initialize(source = ENV.to_h)
      @vars = source.dup
      @exported = source.keys.to_set
      @readonly = Set.new
    end

    sig { params(name: String).returns(T.nilable(String)) }
    def get(name)
      @vars[name]
    end

    sig { params(name: String, value: T.untyped).returns(String) }
    def assign(name, value)
      raise ReadonlyError, "#{name}: is read only" if @readonly.include?(name)

      @vars[name] = value.to_s
    end

    sig { params(name: String).void }
    def export(name)
      @exported.add(name)
    end

    sig { params(name: String).void }
    def readonly(name)
      @readonly.add(name)
    end

    sig { params(name: String).void }
    def unset(name)
      raise ReadonlyError, "#{name}: is read only" if @readonly.include?(name)

      @vars.delete(name)
      @exported.delete(name)
    end

    sig { returns(T::Hash[String, String]) }
    def exported
      # *@exported.to_a: splat needs an Array (Set splats via to_a at runtime, but
      # the checker won't); slice keeps @vars's own order, so this is unchanged.
      @vars.slice(*@exported.to_a)
    end
  end
end
