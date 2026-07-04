# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Small typed adapter for the StringScanner one-character lookahead pattern
    # shared by the shell word scanners. StringScanner#peek is a library boundary;
    # callers use this predicate instead of repeating the comparison everywhere.
    module ScannerPredicates
      extend T::Sig

      private

      sig { params(char: String).returns(T::Boolean) }
      def peek?(char)
        @scanner.peek(1) == char
      end
    end
  end
end
