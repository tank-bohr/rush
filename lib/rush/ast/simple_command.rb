# frozen_string_literal: true

module Rush
  module AST
    # `cmd arg1 arg2` — a list of Words. Assignments and redirects are added in
    # later phases; for now execution just expands the words and dispatches.
    class SimpleCommand < Node
      attr_reader :words

      def initialize(words)
        super()
        @words = words
      end

      def execute(executor) = executor.run_simple(self)
    end
  end
end
