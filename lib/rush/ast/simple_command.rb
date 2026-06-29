# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `name=val ... cmd arg ... >file` — variable assignments, argv words and
    # redirections (in source order within each group).
    class SimpleCommand < Node
      attr_reader :assignments, :words, :redirects

      def initialize(assignments, words, redirects)
        super()
        @assignments = assignments
        @words = words
        @redirects = redirects
      end

      def execute(executor)
        executor.run_simple(self)
      end
    end
  end
end
