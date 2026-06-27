# frozen_string_literal: true

module Rush
  module AST
    # A pipeline of one or more commands. A single command runs in-process (so
    # builtins affect the shell); a multi-stage pipeline forks each stage via
    # PipelineRunner.
    class Pipeline < Node
      attr_reader :commands

      def initialize(commands)
        super()
        @commands = commands
      end

      def execute(executor)
        return executor.run(commands.first) if commands.one?

        PipelineRunner.new(executor, commands).call
      end
    end
  end
end
