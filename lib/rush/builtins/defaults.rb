# typed: true
# frozen_string_literal: true

module Rush
  # The shell's builtin commands and the default name -> implementation table.
  module Builtins
    extend T::Sig

    # The builtins available in Slice 1. Later slices extend this table.
    DEFAULTS = {
      ':' => Colon, 'true' => True, 'false' => False,
      'echo' => Echo, 'exit' => Exit, 'pwd' => Pwd, 'cd' => Cd,
      'break' => Break, 'continue' => Continue, 'return' => Return,
      'test' => Test, '[' => Test, 'set' => Set, 'shift' => Shift,
      'export' => Export, 'unset' => Unset, 'eval' => Eval, 'read' => Read,
      'printf' => Printf, '.' => Dot, 'readonly' => Readonly, 'exec' => Exec,
      'local' => Local, 'type' => Type, 'command' => Command, 'trap' => Trap,
      'kill' => Kill, 'alias' => Alias, 'unalias' => Unalias,
      'hash' => Hash, 'times' => Times
    }.freeze

    sig { returns(T.untyped) }
    def self.default_registry
      Registry.new.tap { |registry| DEFAULTS.each { |name, klass| registry.register(name, klass) } }
    end
  end
end
