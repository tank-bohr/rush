# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `name() compound-command` — registers the body in the function table and
    # succeeds. The body runs (in the current shell) when the name is invoked.
    class FunctionDef < Node
      attr_reader :name, :body

      def initialize(name, body)
        super()
        @name = name
        @body = body
      end

      def execute(executor)
        executor.state.functions.define(name, body)
        Status.success
      end
    end
  end
end
