# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `for name [in words]; do body; done`. With an explicit word list the words
    # are expanded (and field-split); with no `in` clause the loop iterates over
    # the positional parameters ($@).
    class For < Node
      attr_reader :name, :words, :body

      def initialize(name, words, body)
        super()
        @name = name
        @words = words
        @body = body
      end

      def execute(executor)
        ForRunner.new(executor, name, values(executor), body).call
      end

      private

      def values(executor)
        words ? executor.expander.expand(words) : executor.state.positional.to_a
      end
    end
  end
end
