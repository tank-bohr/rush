# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `{ list; }` — groups commands without a subshell, so they run in the
    # current shell environment. (Redirections on the group arrive with the
    # fd-management slice.)
    class BraceGroup < Node
      attr_reader :body

      def initialize(body)
        super()
        @body = body
      end

      def execute(executor)
        executor.run(body)
      end
    end
  end
end
