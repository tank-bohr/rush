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
      argv = @executor.expander.expand(@command.words)
      return run_bare if argv.empty?

      trace(argv)
      run_command(argv)
    end

    private

    def trace(argv)
      @executor.io.get(2).puts("+ #{argv.join(' ')}") if @executor.state.option?(:xtrace)
    end

    def run_bare
      build_io # opens/truncates redirect targets for their side effects
      @command.assignments.each { |assignment| persist(assignment) }
      Status.success
    end

    # POSIX command search: special builtin, then function (so a function may
    # override a regular builtin), then regular builtin, then PATH.
    def run_command(argv)
      io = build_io
      dispatch(argv, io)
    end

    def dispatch(argv, io)
      name = argv.first
      return builtin(argv, io) if special?(name)
      return run_function(argv) if @executor.state.functions.key?(name)
      return builtin(argv, io) if @executor.builtins.key?(name)

      External.new(@executor, argv, io, command_env).call
    end

    def builtin(argv, io) = @executor.builtins.fetch(argv.first).new(@executor, argv, io).call

    def special?(name) = CommandLookup::SPECIAL.include?(name) && @executor.builtins.key?(name)

    def run_function(argv)
      body = @executor.state.functions.fetch(argv.first)
      FunctionRunner.new(@executor, body, argv.drop(1)).call
    end

    def build_io = @executor.apply_redirects(@command.redirects, @base_io)

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
