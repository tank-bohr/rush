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

    def run_command(argv)
      io = build_io
      builtin = @executor.builtins.fetch(argv.first)
      return builtin.new(@executor, argv, io).call if builtin
      return run_function(argv) if @executor.state.functions.key?(argv.first)

      External.new(@executor, argv, io, command_env).call
    end

    def run_function(argv)
      body = @executor.state.functions.fetch(argv.first)
      FunctionRunner.new(@executor, body, argv.drop(1)).call
    end

    def build_io
      @command.redirects.reduce(@base_io) { |io, redirect| apply(io, redirect) }
    end

    def apply(io, redirect)
      applier = @executor.redirections.fetch(redirect.kind)
      applier.apply(redirect, value(redirect.target), io, @executor.system)
    end

    def command_env
      @command.assignments.each_with_object(@executor.state.environment.exported) do |assignment, env|
        env[assignment.name] = assigned(assignment.value)
      end
    end

    def persist(assignment)
      @executor.state.environment.assign(assignment.name, assigned(assignment.value))
    end

    def value(word) = @executor.expander.expand_value(word)

    def assigned(word) = @executor.expander.expand_value(word, tilde: :assignment)
  end
end
