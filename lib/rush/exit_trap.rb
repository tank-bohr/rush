# typed: true
# frozen_string_literal: true

module Rush
  # Owns the one-shot EXIT-trap lifecycle, terminating-status context and fatal
  # error boundary. Ordinary delivered traps use TrapRunner's recoverable policy;
  # EXIT runs at shell teardown and therefore converts fatal shell errors to 2.
  class ExitTrap
    extend T::Sig

    # Trap source paired with the shell status being terminated.
    Execution = Data.define(:source, :code)

    sig { params(executor: Executor).void }
    def initialize(executor)
      @executor = executor
      @state = executor.state
      @exiting = T.let(nil, T.nilable(Integer))
      @fired = false
    end

    sig { params(code: Integer).returns(Integer) }
    def run(code)
      action = claim_action
      return code unless action

      @state.record_status(Status.new(code))
      fire(Execution.new(action, code))
    end

    sig { returns(Integer) }
    def status
      @exiting || @state.last_status.exitstatus
    end

    private

    sig { returns(T.nilable(String)) }
    def claim_action
      return if @fired

      @fired = true
      @state.traps.action(Signals::EXIT)
    end

    sig { params(execution: Execution).returns(Integer) }
    def fire(execution)
      exit_result(execution)
    rescue ParseError, ExpansionError, ReadonlyError, BuiltinError => e
      abort(e)
    end

    sig { params(execution: Execution).returns(Integer) }
    def exit_result(execution)
      control_result(execution)
    rescue ExitSignal => e
      e.code
    end

    sig { params(execution: Execution).returns(Integer) }
    def control_result(execution)
      run_execution(execution)
    rescue LoopControl, ReturnSignal
      execution.code
    end

    sig { params(execution: Execution).returns(Integer) }
    def run_execution(execution)
      source, code = execution.deconstruct
      with_status(code) { evaluate(source) }
      code
    end

    sig { params(error: Error).returns(Integer) }
    def abort(error)
      @executor.system.stderr.puts("rush: #{error.message}")
      @state.record_status(Status.new(2))
      2
    end

    sig do
      type_parameters(:U)
        .params(code: Integer, blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def with_status(code, &blk)
      @exiting = code
      yield
    ensure
      @exiting = nil
    end

    sig { params(action: String).void }
    def evaluate(action)
      @executor.run(Parser.new(Lexer.new(action, aliases: @state.aliases)).parse)
    end
  end
end
