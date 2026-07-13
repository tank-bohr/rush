# typed: true
# frozen_string_literal: true

module Rush
  # Runs a SimpleCommand: expand argv, classify it for ordinary execution,
  # evaluate redirections into a per-command IoTable, then apply the resolution's
  # assignment and redirect policies while dispatching the selected command kind.
  class CommandRunner
    extend T::Sig

    sig { params(executor: Executor, command: AST::SimpleCommand, base_io: IoTable).void }
    def initialize(executor, command, base_io = executor.io)
      @executor = executor
      @command = command
      @base_io = base_io
      @assignments = CommandAssignments.new(command.assignments, executor.expander)
    end

    sig { returns(Status) }
    def call
      @executor.reset_cmd_sub_status
      argv = @executor.expander.expand(@command.words)
      return run_bare if argv.empty?

      trace(argv)
      run_command(argv)
    end

    private

    # POSIX 2.5.3: each xtrace line goes to stderr prefixed with the expanded
    # PS4 (parameter expansion only — see Prompt). The standard repeats PS4's
    # first character per level of indirection; rush's tracer has no nesting
    # depth (and dash never repeats), so a single prefix is correct here.
    sig { params(argv: T::Array[String]).void }
    def trace(argv)
      return unless @executor.state.options.on?(:xtrace)

      @executor.io.get(2).puts("#{Prompt.new(@executor).trace}#{argv.join(' ')}")
    end

    # No command word: perform redirections then assignments (POSIX order), and
    # take the status of the last command substitution either ran (Status.success
    # when none did), as published via the executor's cmd-sub channel.
    # with_redirects opens/truncates the targets for their side effects, then
    # flushes+closes them after the assignments so a later command sees the data.
    sig { returns(Status) }
    def run_bare
      @executor.redirect_scope.with_redirects(@command.redirects, @base_io) { |io| persist_assignments(io) }
    end

    sig { params(io: IoTable).returns(Status) }
    def persist_assignments(io)
      @executor.with_io(io) do
        @assignments.persist_to(@executor.state.variables)
        @executor.cmd_sub_status
      end
    end

    # POSIX command search: special builtin, then function (so a function may
    # override a regular builtin), then regular builtin, then PATH. A redirect
    # error leaves a regular command unrun with status 2 (RedirectError reaches
    # Executor#run), but on a special builtin it aborts the shell (POSIX 2.8.1),
    # so it is re-raised as a fatal BuiltinError.
    sig { params(argv: T::Array[String]).returns(Status) }
    def run_command(argv)
      resolution = CommandResolution.for_execution(argv.fetch(0), @executor.state.functions, @executor.builtins)
      dispatch_with_redirects(resolution, argv)
    end

    sig { params(resolution: CommandResolution, argv: T::Array[String]).returns(Status) }
    def dispatch_with_redirects(resolution, argv)
      @executor.redirect_scope.with_redirects(@command.redirects, @base_io) { |io| dispatch(resolution, argv, io) }
    rescue RedirectError => e
      raise unless resolution.fatal_redirect?

      raise BuiltinError, e.message
    end

    sig { params(resolution: CommandResolution, argv: T::Array[String], io: IoTable).returns(Status) }
    def dispatch(resolution, argv, io)
      environment = command_env(io)
      apply_assignment_policy(resolution, argv, io, environment)
    end

    sig do
      params(resolution: CommandResolution, argv: T::Array[String], io: IoTable,
             environment: T::Hash[String, String]).returns(Status)
    end
    def apply_assignment_policy(resolution, argv, io, environment)
      return persistent_dispatch(argv, io, environment) if resolution.persistent_assignments?
      return temporary_dispatch(resolution, argv, io, environment) if resolution.temporary_assignments?

      external(argv, io, environment)
    end

    sig { params(argv: T::Array[String], io: IoTable, environment: T::Hash[String, String]).returns(Status) }
    def persistent_dispatch(argv, io, environment)
      @assignments.persist_environment(environment, @executor.state.variables)
      invoke_builtin(argv, io, environment)
    end

    sig do
      params(resolution: CommandResolution, argv: T::Array[String], io: IoTable,
             environment: T::Hash[String, String]).returns(Status)
    end
    def temporary_dispatch(resolution, argv, io, environment)
      values = @assignments.temporary_environment(environment)
      @executor.state.variables.with_temporary(values) { invoke_temporary(resolution, argv, io, environment) }
    end

    sig do
      params(resolution: CommandResolution, argv: T::Array[String], io: IoTable,
             environment: T::Hash[String, String]).returns(Status)
    end
    def invoke_temporary(resolution, argv, io, environment)
      resolution.function? ? invoke_function(argv, io) : invoke_builtin(argv, io, environment)
    end

    sig { params(argv: T::Array[String], io: IoTable, environment: T::Hash[String, String]).returns(Status) }
    def external(argv, io, environment)
      @assignments.validate(@executor.state.variables)
      External.new(@executor, argv, io, environment).call(@executor.job_control.job_text(@command))
    end

    sig { params(argv: T::Array[String], io: IoTable, environment: T::Hash[String, String]).returns(Status) }
    # A builtin reading from or writing to a fd closed by n>&- raises EBADF; like
    # dash, that fails the command (status 1) without killing the shell.
    def invoke_builtin(argv, io, environment)
      @executor.builtins.fetch(argv.fetch(0)).new(@executor, argv, io, environment).call
    rescue Errno::EBADF
      Status.new(1)
    end

    # A function runs in the current shell, not a subshell. The call's redirects
    # (if any) bind the whole body and are torn down when it returns — even an
    # `exec` inside is scoped to them, as dash does. With no redirects the body
    # shares the shell's io table so an `exec` inside *persists*, so wrap in
    # with_io only when a redirect actually layered a new table over the base.
    sig { params(argv: T::Array[String], io: IoTable).returns(Status) }
    def invoke_function(argv, io)
      body = @executor.state.functions.fetch(argv.fetch(0))
      run = -> { FunctionRunner.new(@executor, body, argv.drop(1)).call }
      io.equal?(@executor.io) ? run.call : @executor.with_io(io, &run)
    end

    sig { params(io: IoTable).returns(T::Hash[String, String]) }
    def command_env(io)
      @executor.with_io(io) { @assignments.environment_for(@executor.state.variables) }
    end
  end
end
