# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `for name [in words]; do body; done`. With an explicit word list the words
    # are expanded (and field-split); with no `in` clause the loop iterates over
    # the positional parameters ($@).
    class For < Node
      extend T::Sig

      attr_reader :name, :words, :body

      sig { params(name: String, words: T.nilable(T::Array[Word]), body: Node).void }
      def initialize(name, words, body)
        super()
        @name = name
        @words = words
        @body = body
      end

      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        ForRunner.new(executor, name, values(executor), body).call
      end

      private

      sig { params(executor: Executor).returns(T::Array[String]) }
      def values(executor)
        words ? executor.expander.expand(words) : executor.state.positional.to_a
      end
    end
  end
end
