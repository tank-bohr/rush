# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `{ list; }` — groups commands without a subshell, so they run in the
    # current shell environment. (Redirections on the group arrive with the
    # fd-management slice.)
    class BraceGroup < Node
      extend T::Sig

      attr_reader :body

      sig { params(body: Node).void }
      def initialize(body)
        super()
        @body = body
      end

      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        executor.run(body)
      end
    end
  end
end
