# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `( list )` — runs the list in a subshell (a forked child) so cd and
    # variable changes do not affect the current shell. Its status is the list's.
    class Subshell < Node
      extend T::Sig

      attr_reader :body

      sig { params(body: Node).void }
      def initialize(body)
        super()
        @body = body
      end

      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        SubshellRunner.new(executor, body).call
      end
    end
  end
end
