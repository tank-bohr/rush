# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `name=val ... cmd arg ... >file` — variable assignments, argv words and
    # redirections (in source order within each group).
    class SimpleCommand < Node
      extend T::Sig

      attr_reader :assignments, :words, :redirects

      sig { params(assignments: T::Array[Assignment], words: T::Array[Word], redirects: T::Array[Redirect]).void }
      def initialize(assignments, words, redirects)
        super()
        @assignments = assignments
        @words = words
        @redirects = redirects
      end

      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        executor.run_simple(self)
      end
    end
  end
end
