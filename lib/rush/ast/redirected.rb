# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # A compound command (group, subshell, loop, if, case) carrying redirections
    # on the whole command: they build a base IoTable that every command in the
    # body inherits, restored once the command finishes. Its status is the body's.
    class Redirected < Node
      extend T::Sig

      attr_reader :command, :redirects

      sig { params(command: Node, redirects: T::Array[Redirect]).void }
      def initialize(command, redirects)
        super()
        @command = command
        @redirects = redirects
      end

      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        executor.run_redirected(command, redirects)
      end
    end
  end
end
