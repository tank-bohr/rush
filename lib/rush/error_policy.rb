# typed: true
# frozen_string_literal: true

module Rush
  # Pure classification table for Rush::Error at runtime boundaries. The table
  # deliberately owns no reporting, status mutation, I/O, or EXIT lifecycle;
  # each boundary applies the decision in its own environment.
  class ErrorPolicy
    extend T::Sig

    CONTEXTS = %i[batch interactive subshell command signal_trap exit_trap].freeze
    DIAGNOSTIC_DECISIONS = %i[abort2 recover2 demote2].freeze

    OPERATIONAL = {
      batch: :abort2, interactive: :recover2, subshell: :abort2,
      command: :demote2, signal_trap: :ignore, exit_trap: :abort2
    }.freeze
    OWNED = {
      batch: :propagate, interactive: :propagate, subshell: :abort2,
      command: :propagate, signal_trap: :propagate, exit_trap: :propagate
    }.freeze
    INTERRUPT = {
      batch: :interrupt130, interactive: :recover130, subshell: :abort2,
      command: :propagate, signal_trap: :propagate, exit_trap: :propagate
    }.freeze
    EXIT = {
      batch: :propagate, interactive: :propagate, subshell: :return_code,
      command: :propagate, signal_trap: :propagate, exit_trap: :override_code
    }.freeze
    RETURN = {
      batch: :propagate, interactive: :ignore, subshell: :return_code,
      command: :propagate, signal_trap: :ignore, exit_trap: :preserve_code
    }.freeze
    LOOP = {
      batch: :propagate, interactive: :propagate, subshell: :last_status,
      command: :propagate, signal_trap: :ignore, exit_trap: :preserve_code
    }.freeze
    BUILTIN = OPERATIONAL.merge(signal_trap: :propagate).freeze

    MATRIX = {
      Error => OWNED,
      ParseError => OPERATIONAL,
      IncompleteInput => OPERATIONAL,
      ExpansionError => OPERATIONAL,
      InvocationError => OWNED,
      Interrupted => INTERRUPT,
      TestError => OWNED,
      ReadonlyError => OPERATIONAL,
      BuiltinError => BUILTIN,
      RedirectError => OWNED,
      JobError => OWNED,
      ExitSignal => EXIT,
      LoopControl => LOOP,
      BreakSignal => LOOP,
      ContinueSignal => LOOP,
      ReturnSignal => RETURN
    }.freeze

    sig { params(context: Symbol, error: Error).returns(Symbol) }
    def self.decision(context, error)
      MATRIX.fetch(error.class).fetch(context)
    end
  end
end
