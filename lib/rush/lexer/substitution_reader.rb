# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Reads the raw body of a command substitution from the shared scanner:
    # $( ... ) with balanced parentheses, or ` ... ` up to the next backtick.
    # The body is re-parsed and executed at expansion time.
    class SubstitutionReader
      extend T::Sig

      DEPTH_DELTA = { '(' => 1, ')' => -1 }.freeze

      sig { params(scanner: StringScanner).void }
      def initialize(scanner)
        @scanner = scanner
        @depth = 0
      end

      sig { returns(String) }
      def parens
        @depth = 1
        (+'').tap { |body| body << paren_char until @depth.zero? }
      end

      sig { returns(T.nilable(String)) }
      def backticks
        body = @scanner.scan(/[^`]*/)
        raise IncompleteInput, 'unterminated `' unless @scanner.scan('`')

        body
      end

      # Read the body of $(( ... )) after the leading `((`, up to the matching
      # `))`, allowing balanced inner parentheses.
      sig { returns(String) }
      def arithmetic
        @depth = 0
        collect(+'')
      end

      private

      sig { params(body: String).returns(String) }
      def collect(body)
        char = arith_char
        return body unless char

        collect(body << char)
      end

      sig { returns(T.nilable(String)) }
      def arith_char
        raise IncompleteInput, 'unterminated $((' if @scanner.eos?

        char = @scanner.getch
        return arith_close if char == ')'

        @depth += 1 if char == '('
        char
      end

      sig { returns(T.nilable(String)) }
      def arith_close
        return ')'.tap { @depth -= 1 } if @depth.nonzero?
        raise(ParseError, 'arithmetic: malformed') unless @scanner.scan(')')

        nil
      end

      sig { returns(String) }
      def paren_char
        raise IncompleteInput, 'unterminated $(' if @scanner.eos?

        # not eos, so getch is non-nil; .to_s pins it to String for adjust/<<.
        char = @scanner.getch.to_s
        adjust(char)
        @depth.zero? ? '' : char
      end

      sig { params(char: String).void }
      def adjust(char)
        @depth += DEPTH_DELTA.fetch(char, 0)
      end
    end
  end
end
