# frozen_string_literal: true

module Rush
  module AST
    # `( list )` — runs the list in a subshell (a forked child) so cd and
    # variable changes do not affect the current shell. Its status is the list's.
    class Subshell < Node
      attr_reader :body

      def initialize(body)
        super()
        @body = body
      end

      def execute(executor)
        SubshellRunner.new(executor, body).call
      end
    end
  end
end
