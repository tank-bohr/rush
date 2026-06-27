# frozen_string_literal: true

require 'strscan'

module Rush
  module Expansion
    # Expands $(( ... )): first apply parameter expansion and command
    # substitution to the raw text (POSIX treats it like a double-quoted word),
    # then evaluate the result as an integer arithmetic expression.
    class ArithmeticExpander
      def initialize(executor, source)
        @executor = executor
        @source = source
      end

      def expand = Arithmetic::Evaluator.new(@executor).evaluate(expanded).to_s

      private

      def expanded = @executor.expander.expand_value(scanned)

      def scanned = Lexer::WordScanner.new(StringScanner.new(@source), whole: true).scan
    end
  end
end
