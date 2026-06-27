# frozen_string_literal: true

module Rush
  # Runs a SimpleCommand: expand argv, evaluate redirections into a per-command
  # IoTable, then either apply bare assignments (no command word) or dispatch to
  # a builtin / external. Temporary-vs-persistent assignment scoping for special
  # builtins is refined in Phase 2.
  class CommandRunner
    def initialize(executor, command)
      @executor = executor
      @command = command
    end

    def call
      argv = @executor.expander.expand(@command.words)
      argv.empty? ? run_bare : run_command(argv)
    end

    private

    def run_bare
      build_io # opens/truncates redirect targets for their side effects
      @command.assignments.each { |assignment| persist(assignment) }
      Status.success
    end

    def run_command(argv)
      io = build_io
      builtin = @executor.builtins.fetch(argv.first)
      return builtin.new(@executor, argv, io).call if builtin

      External.new(@executor, argv, io, command_env).call
    end

    def build_io
      @command.redirects.reduce(@executor.io) { |io, redirect| apply(io, redirect) }
    end

    def apply(io, redirect)
      applier = @executor.redirections.fetch(redirect.kind)
      applier.apply(redirect, value(redirect.target), io, @executor.system)
    end

    def command_env
      @command.assignments.each_with_object(@executor.state.environment.exported) do |assignment, env|
        env[assignment.name] = value(assignment.value)
      end
    end

    def persist(assignment)
      @executor.state.environment.assign(assignment.name, value(assignment.value))
    end

    def value(word) = @executor.expander.expand_value(word)
  end
end
