# typed: true
# frozen_string_literal: true

module Rush
  # The mutable shell state threaded through execution: the variable environment,
  # the last command's status ($?, the one field with behaviour here), the shell
  # name ($0), and the session sub-objects it bundles for the rest of the
  # interpreter to drive directly — the variable Scope (local scoping + cwd),
  # LoopNesting, Options, Positional, the function/alias/trap tables and the
  # command-location cache.
  class ShellState
    extend T::Sig

    sig { returns(Environment) }
    attr_reader :environment

    sig { returns(FunctionTable) }
    attr_reader :functions

    sig { returns(TrapTable) }
    attr_reader :traps

    sig { returns(AliasTable) }
    attr_reader :aliases

    sig { returns(T::Hash[String, String]) }
    attr_reader :command_hash

    sig { returns(String) }
    attr_reader :name

    sig { returns(Scope) }
    attr_reader :scope

    sig { returns(LoopNesting) }
    attr_reader :loops

    sig { returns(Options) }
    attr_reader :options

    sig { returns(Status) }
    attr_reader :last_status

    sig { returns(Positional) }
    attr_reader :positional

    sig { params(environment: Environment, name: String).void }
    def initialize(environment: Environment.new, name: 'rush')
      @environment = environment
      @name = name
      @scope = Scope.new(environment)
      @traps = TrapTable.new
      @last_status = Status.success
      @loops = LoopNesting.new
      @options = Options.new
      @positional = Positional.new
      @functions = FunctionTable.new
      @aliases = AliasTable.new
      @command_hash = {}
    end

    # The last command's exit status ($?), recorded after each command runs.
    sig { params(status: Status).returns(Status) }
    def record_status(status)
      @last_status = status
    end
  end
end
