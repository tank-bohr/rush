# frozen_string_literal: true

module Rush
  module AST
    # A pipeline of one or more commands, optionally negated with `!`. A single
    # command runs in-process (so builtins affect the shell); a multi-stage
    # pipeline forks each stage via PipelineRunner. Negation inverts the status.
    class Pipeline < Node
      attr_reader :commands, :negate

      def initialize(commands, negate)
        super()
        @commands = commands
        @negate = negate
      end

      # A negated pipeline (`! cmd`) is exempt from errexit and runs its stages in
      # a tested context; otherwise the leaf status is the errexit check point.
      def execute(executor)
        return invert(executor.tested { run_stages(executor) }) if negate

        executor.exit_on_error(run_stages(executor))
      end

      private

      def run_stages(executor)
        commands.one? ? executor.run(commands.first) : PipelineRunner.new(executor, commands).call
      end

      def invert(status)
        status.success? ? Status.failure : Status.success
      end
    end
  end
end
