# frozen_string_literal: true

module Rush
  # Runs a SimpleCommand: expand its words to argv, then dispatch to a builtin
  # or an external process. Assignments, redirects and functions arrive later.
  class CommandRunner
    def initialize(executor, command)
      @executor = executor
      @command = command
    end

    def call
      argv = @executor.expander.expand(@command.words)
      return @executor.state.last_status if argv.empty?

      dispatch(argv)
    end

    private

    def dispatch(argv)
      builtin = @executor.builtins.fetch(argv.first)
      return builtin.new(@executor, argv).call if builtin

      External.new(@executor, argv).call
    end
  end
end
