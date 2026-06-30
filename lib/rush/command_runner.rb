# typed: true
# frozen_string_literal: true

module Rush
  # Runs a SimpleCommand: expand argv, evaluate redirections into a per-command
  # IoTable, then either apply bare assignments (no command word) or dispatch to
  # a builtin / external. Temporary-vs-persistent assignment scoping for special
  # builtins is refined in Phase 2.
  class CommandRunner
    extend T::Sig

    sig { params(executor: Executor, command: AST::SimpleCommand, base_io: IoTable).void }
    def initialize(executor, command, base_io = executor.io)
      @executor = executor
      @command = command
      @base_io = base_io
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

    sig { params(argv: T::Array[String]).void }
    def trace(argv)
      @executor.io.get(2).puts("+ #{argv.join(' ')}") if @executor.state.options.on?(:xtrace)
    end

    # No command word: perform redirections then assignments (POSIX order), and
    # take the status of the last command substitution either ran (Status.success
    # when none did), as published via the executor's cmd-sub channel.
    # with_redirects opens/truncates the targets for their side effects, then
    # flushes+closes them after the assignments so a later command sees the data.
    sig { returns(Status) }
    def run_bare
      @executor.with_redirects(@command.redirects, @base_io) do
        @command.assignments.each { |assignment| persist(assignment) }
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
      @executor.with_redirects(@command.redirects, @base_io) { |io| dispatch(argv, io) }
    rescue RedirectError => e
      raise BuiltinError, e.message if special?(argv.first)

      raise
    end

    sig { params(argv: T::Array[String], io: T.untyped).returns(Status) }
    def dispatch(argv, io)
      name = argv.fetch(0)
      return builtin(argv, io) if special?(name)
      return run_function(argv, io) if @executor.state.functions.key?(name)
      return builtin(argv, io) if @executor.builtins.key?(name)

      External.new(@executor, argv, io, command_env).call
    end

    # A builtin reading from or writing to a fd closed by n>&- raises EBADF; like
    # dash, that fails the command (status 1) without killing the shell.
    sig { params(argv: T::Array[String], io: T.untyped).returns(Status) }
    def builtin(argv, io)
      @executor.builtins.fetch(argv.first).new(@executor, argv, io).call
    rescue Errno::EBADF
      Status.new(1)
    end

    sig { params(name: T.nilable(String)).returns(T::Boolean) }
    def special?(name)
      CommandLookup::SPECIAL.include?(name) && @executor.builtins.key?(name)
    end

    # A function runs in the current shell, not a subshell. The call's redirects
    # (if any) bind the whole body and are torn down when it returns — even an
    # `exec` inside is scoped to them, as dash does. With no redirects the body
    # shares the shell's io table so an `exec` inside *persists*, so wrap in
    # with_io only when a redirect actually layered a new table over the base.
    sig { params(argv: T::Array[String], io: T.untyped).returns(Status) }
    def run_function(argv, io)
      body = @executor.state.functions.fetch(argv.fetch(0))
      run = -> { FunctionRunner.new(@executor, body, argv.drop(1)).call }
      io.equal?(@executor.io) ? run.call : @executor.with_io(io, &run)
    end

    sig { returns(T::Hash[String, String]) }
    def command_env
      @command.assignments.each_with_object(@executor.state.environment.exported) do |assignment, env|
        env[assignment.name] = assigned(assignment.value)
      end
    end

    sig { params(assignment: AST::Assignment).void }
    def persist(assignment)
      @executor.state.environment.assign(assignment.name, assigned(assignment.value))
    end

    sig { params(word: AST::Word).returns(String) }
    def assigned(word)
      @executor.expander.expand_value(word, tilde: :assignment)
    end
  end
end
