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

    def get(name) = @vars[name]

    def assign(name, value)
      raise ReadonlyError, "#{name}: is read only" if @readonly.include?(name)

      @vars[name] = value.to_s
    end

    def export(name) = @exported.add(name)

    def readonly(name) = @readonly.add(name)

    def unset(name)
      raise ReadonlyError, "#{name}: is read only" if @readonly.include?(name)

      @vars.delete(name)
      @exported.delete(name)
    end

    def exported = @vars.slice(*@exported)
  end
end
