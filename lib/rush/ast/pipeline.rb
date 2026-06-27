# frozen_string_literal: true

module Rush
  module AST
    # A pipeline of one or more commands. A single command runs in-process so
    # builtins affect the shell; multi-stage pipelines (forking every stage via
    # PipelineRunner) arrive with the fork slice.
    class Pipeline < Node
      attr_reader :commands

      def initialize(commands)
        super()
        @commands = commands
      end

      def execute(executor) = executor.run(commands.first)
    end
  end
end
