# typed: true
# frozen_string_literal: true

module Rush
  # The mutable shell state threaded through execution: shell variables,
  # the last command's status ($?, the one field with behaviour here), the shell
  # name ($0), and the session sub-objects it bundles for the rest of the
  # interpreter to drive directly — LoopNesting, Options, Positional, the
  # function/alias/trap tables and the command-location cache.
  class ShellState
    extend T::Sig

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

    sig { returns(ShellVariables) }
    attr_reader :variables

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
      @name = name
      @variables = ShellVariables.new(environment)
      @traps = TrapTable.new
      @last_status = Status.success
      @loops = LoopNesting.new
      @options = Options.new
      @positional = Positional.new
      @function_frame = FunctionFrame.new(variables: @variables, loops: @loops, positional: @positional)
      @functions = FunctionTable.new
      @aliases = AliasTable.new
      @command_hash = {}
    end

    sig do
      type_parameters(:U)
        .params(args: T::Array[String], blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def with_function_frame(args, &blk)
      @function_frame.call(args, &blk)
    end

    # The last command's exit status ($?), recorded after each command runs.
    sig { params(status: Status).returns(Status) }
    def record_status(status)
      @last_status = status
    end
  end
end
