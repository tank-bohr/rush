# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # A pipeline of one or more commands, optionally negated with `!`. A single
    # command runs in-process (so builtins affect the shell); a multi-stage
    # pipeline forks each stage via PipelineRunner. Negation inverts the status.
    class Pipeline < Node
      extend T::Sig

      sig { returns(T::Array[Node]) }
      attr_reader :commands

      sig { returns(T::Boolean) }
      attr_reader :negate

      sig { params(commands: T::Array[Node], negate: T::Boolean).void }
      def initialize(commands, negate)
        @commands = commands
        @negate = negate
      end

      # A negated pipeline (`! cmd`) is exempt from errexit and runs its stages in
      # a tested context; otherwise the leaf status is the errexit check point.
      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        return invert(executor.errexit.tested { run_stages(executor) }) if negate

        executor.errexit.exit_on_error(run_stages(executor))
      end

      private

      sig { params(executor: Executor).returns(Status) }
      def run_stages(executor)
        case commands
        in [command] then executor.run(command)
        else PipelineRunner.new(executor, commands).call
        end
      end

      sig { params(status: Status).returns(Status) }
      def invert(status)
        status.success? ? Status.failure : Status.success
      end
    end
  end
end
