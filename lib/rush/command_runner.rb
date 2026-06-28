# frozen_string_literal: true

module Rush
  # Runs a SimpleCommand: expand argv, evaluate redirections into a per-command
  # IoTable, then either apply bare assignments (no command word) or dispatch to
  # a builtin / external. Temporary-vs-persistent assignment scoping for special
  # builtins is refined in Phase 2.
  class CommandRunner
    def initialize(executor, command, base_io = executor.io)
      @executor = executor
      @command = command
      @base_io = base_io
    end

    def call
      @executor.reset_cmd_sub_status
      argv = @executor.expander.expand(@command.words)
      return run_bare if argv.empty?

      trace(argv)
      run_command(argv)
    end

    private

    def trace(argv)
      @executor.io.get(2).puts("+ #{argv.join(' ')}") if @executor.state.option?(:xtrace)
    end

    # No command word: perform redirections then assignments (POSIX order), and
    # take the status of the last command substitution either ran (Status.success
    # when none did), as published via the executor's cmd-sub channel.
    # with_redirects opens/truncates the targets for their side effects, then
    # flushes+closes them after the assignments so a later command sees the data.
    def run_bare
      @executor.with_redirects(@command.redirects, @base_io) do
        @command.assignments.each { |assignment| persist(assignment) }
        @executor.cmd_sub_status
      end
    end

    # POSIX command search: special builtin, then function (so a function may
    # override a regular builtin), then regular builtin, then PATH.
    def run_command(argv)
      @executor.with_redirects(@command.redirects, @base_io) { |io| dispatch(argv, io) }
    end

    def dispatch(argv, io)
      name = argv.first
      return builtin(argv, io) if special?(name)
      return run_function(argv) if @executor.state.functions.key?(name)
      return builtin(argv, io) if @executor.builtins.key?(name)

      External.new(@executor, argv, io, command_env).call
    end

    # A builtin reading from or writing to a fd closed by n>&- raises EBADF; like
    # dash, that fails the command (status 1) without killing the shell.
    def builtin(argv, io)
      @executor.builtins.fetch(argv.first).new(@executor, argv, io).call
    rescue Errno::EBADF
      Status.new(1)
    end

    def special?(name) = CommandLookup::SPECIAL.include?(name) && @executor.builtins.key?(name)

    def run_function(argv)
      body = @executor.state.functions.fetch(argv.first)
      FunctionRunner.new(@executor, body, argv.drop(1)).call
    end

    def command_env
      @command.assignments.each_with_object(@executor.state.environment.exported) do |assignment, env|
        env[assignment.name] = assigned(assignment.value)
      end
    end

    def persist(assignment)
      @executor.state.environment.assign(assignment.name, assigned(assignment.value))
    end

    def assigned(word) = @executor.expander.expand_value(word, tilde: :assignment)
  end
end
