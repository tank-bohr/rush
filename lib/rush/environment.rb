# typed: true
# frozen_string_literal: true

module Rush
  # Shell variables and the subset marked for export. The exported slice is what
  # external children receive (see SystemCalls#spawn).
  class Environment
    extend T::Sig

    VariableState = T.type_alias do
      [T::Boolean, T.nilable(String), T::Boolean, T::Boolean]
    end
    DynamicState = T.type_alias { T.any(T::Boolean, Symbol) }
    Snapshot = T.type_alias { [T::Hash[String, VariableState], DynamicState] }

    sig { params(source: T::Hash[String, String]).void }
    def initialize(source = ENV.to_h)
      @vars = source.dup
      @exported = source.keys.to_set
      @readonly = Set.new
      @dynamic_lineno = !@vars.key?('LINENO')
    end

    sig { params(name: String).returns(T.nilable(String)) }
    def get(name)
      @vars.fetch(name, nil)
    end

    sig { params(name: String, value: String).returns(String) }
    def assign(name, value)
      validate_assignment(name)
      @dynamic_lineno &&= name != 'LINENO'
      @vars[name] = value
    end

    sig { params(name: String).void }
    def validate_assignment(name)
      raise ReadonlyError, "#{name}: is read only" if @readonly.include?(name)
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
      validate_assignment(name)
      @dynamic_lineno &&= name != 'LINENO'
      @vars.delete(name)
      @exported.delete(name)
    end

    sig { params(line: Integer).returns(T.nilable(String)) }
    def update_lineno(line)
      @vars['LINENO'] = line.to_s if @dynamic_lineno
    end

    sig { returns(T::Hash[String, String]) }
    def exported
      # *@exported.to_a: splat needs an Array (Set splats via to_a at runtime, but
      # the checker won't); slice keeps @vars's own order, so this is unchanged.
      @vars.slice(*@exported.to_a)
    end

    # Prefix assignments on a regular builtin are visible/exported only for the
    # invocation. Writes to those same names stay temporary; changes to every
    # other shell variable remain live, matching a builtin's in-process effects.
    sig do
      params(values: T::Hash[String, String], blk: T.proc.returns(T.untyped)).returns(T.untyped)
    end
    def with_temporary(values, &blk)
      saved = snapshot(values)
      restore_after(saved) do
        apply_temporary(values)
        yield
      end
    end

    private

    sig { params(saved: Snapshot, blk: T.proc.returns(T.untyped)).returns(T.untyped) }
    def restore_after(saved, &blk)
      yield
    ensure
      restore_snapshot(saved)
    end

    sig { params(values: T::Hash[String, String]).returns(Snapshot) }
    def snapshot(values)
      states = values.keys.to_h { |name| [name, variable_state(name)] }
      dynamic_lineno = values.key?('LINENO') ? @dynamic_lineno : :keep #: dynamic_state
      [states, dynamic_lineno]
    end

    sig { params(name: String).returns(VariableState) }
    def variable_state(name)
      [@vars.key?(name), @vars.fetch(name, nil), @exported.include?(name), @readonly.include?(name)]
    end

    sig { params(values: T::Hash[String, String]).void }
    def apply_temporary(values)
      values.each { |name, value| assign(name, value).tap { export(name) } }
    end

    sig { params(saved: Snapshot).void }
    def restore_snapshot(saved)
      states, dynamic_lineno = saved
      states.each { |name, state| restore_variable(name, state) }
      restore_lineno(dynamic_lineno)
    end

    sig { params(dynamic_lineno: DynamicState).void }
    def restore_lineno(dynamic_lineno)
      return if dynamic_lineno == :keep

      value = T.cast(dynamic_lineno, T::Boolean)
      @dynamic_lineno = value
    end

    sig { params(name: String, state: VariableState).void }
    def restore_variable(name, state)
      present, value, exported, readonly = state
      present ? @vars[name] = T.must(value) : @vars.delete(name)
      exported ? @exported.add(name) : @exported.delete(name)
      readonly ? @readonly.add(name) : @readonly.delete(name)
    end
  end
end
