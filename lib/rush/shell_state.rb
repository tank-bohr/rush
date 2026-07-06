# typed: true
# frozen_string_literal: true

module Rush
  # Original shell and parent process ids used for $$ and PPID.
  ShellProcessIds = Data.define(:shell, :parent) do
    extend T::Sig

    sig { params(system: SystemCalls).returns(ShellProcessIds) }
    def self.for(system)
      new(system.pid, system.ppid)
    end
  end

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

    sig { returns(Integer) }
    attr_reader :shell_pid

    sig { returns(Integer) }
    attr_reader :parent_pid

    sig { returns(ShellVariables) }
    attr_reader :variables

    sig { returns(LoopNesting) }
    attr_reader :loops

    sig { returns(Options) }
    attr_reader :options

    sig { returns(Status) }
    attr_reader :last_status

    sig { returns(T.nilable(Integer)) }
    attr_reader :last_background_pid

    sig { returns(Positional) }
    attr_reader :positional

    sig { returns(GetoptsState) }
    attr_reader :getopts

    sig { returns(ShellParameters) }
    attr_reader :parameters

    # ShellState wires every shell sub-table; helper extraction would hide state.
    # rubocop:disable Metrics/AbcSize
    sig { params(environment: Environment, name: String, positional: T::Array[String], pids: ShellProcessIds).void }
    def initialize(environment: Environment.new, name: 'rush', positional: [], pids: ShellProcessIds.new(0, 0))
      @name = name
      @shell_pid = pids.shell
      @parent_pid = pids.parent
      @variables = ShellVariables.new(environment)
      @variables.assign('PPID', @parent_pid.to_s)
      @traps = TrapTable.new
      @last_status = Status.success
      @last_background_pid = T.let(nil, T.nilable(Integer))
      @loops = LoopNesting.new
      @options = Options.new
      @positional = Positional.new(positional)
      @getopts = GetoptsState.new
      @variables.assign('OPTIND', '1')
      @parameters = ShellParameters.new(self)
      @function_frame = FunctionFrame.new(variables: @variables, loops: @loops, positional: @positional)
      @functions = FunctionTable.new
      @aliases = AliasTable.new
      @command_hash = {}
    end
    # rubocop:enable Metrics/AbcSize

    sig do
      type_parameters(:U)
        .params(args: T::Array[String], blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def with_function_frame(args, &blk)
      @function_frame.call(args, &blk)
    end

    sig do
      type_parameters(:U)
        .params(blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def with_loop(&blk)
      @loops.enter
      yield
    ensure
      @loops.leave
    end

    sig do
      type_parameters(:U)
        .params(blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def preserve_status(&blk)
      saved = @last_status
      yield
    ensure
      @last_status = T.must(saved)
    end

    # Flip a shell option, keeping the side effects options carry in sync
    # (allexport mirrors onto the variable table); shared by the set builtin
    # and invocation flags.
    sig { params(option: Symbol, enabled: T::Boolean).void }
    def set_option(option, enabled)
      @options.set(option, enabled)
      @variables.allexport = enabled if option == :allexport
    end

    # The last command's exit status ($?), recorded after each command runs.
    sig { params(status: Status).returns(Status) }
    def record_status(status)
      @last_status = status
    end

    sig { params(pid: Integer).returns(Integer) }
    def record_background_pid(pid)
      @last_background_pid = pid
    end

    sig { params(line: Integer).void }
    def record_lineno(line)
      @variables.update_lineno(line)
    end
  end
end
