# typed: true
# frozen_string_literal: true

require 'strscan'

module Rush
  module Expansion
    # Expands $(( ... )): first apply parameter expansion and command
    # substitution to the raw text (POSIX treats it like a double-quoted word),
    # then evaluate the result as an integer arithmetic expression.
    class ArithmeticExpander
      extend T::Sig

      sig { params(executor: Executor, source: String).void }
      def initialize(executor, source)
        @executor = executor
        @source = source
      end

      sig { returns(String) }
      def expand
        Arithmetic::Evaluator.new(@executor).evaluate(expanded).to_s
      end

      private

      sig { returns(String) }
      def expanded
        @executor.expander.expand_value(scanned, tilde: :none)
      end

      sig { returns(T.untyped) }
      def scanned
        Lexer::WordScanner.entire(@source)
      end
    end
  end
end
