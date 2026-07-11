# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Reads the raw body of a command substitution from the shared scanner:
    # $( ... ) up to the matching quote-aware `)` (via ParenReader), or
    # ` ... ` up to the next backtick. The body is re-parsed and executed at
    # expansion time.
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
        ParenReader.new(@scanner).read
      end

      sig { returns(String) }
      def backticks
        body = @scanner.scan(/[^`]*/) || ''
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
        piece = arith_char
        return body unless piece

        collect(body << piece)
      end

      sig { returns(T.nilable(String)) }
      def arith_char
        raise IncompleteInput, 'unterminated $((' if @scanner.eos?

        adjust_arithmetic(@scanner.getch)
      end

      sig { params(token: T.nilable(String)).returns(T.nilable(String)) }
      def adjust_arithmetic(token)
        delta = DEPTH_DELTA.fetch(token, 0)
        return arith_close if delta.negative?

        @depth += delta
        token
      end

      sig { returns(T.nilable(String)) }
      def arith_close
        return ')'.tap { @depth -= 1 } if @depth.nonzero?
        raise(ParseError, 'arithmetic: malformed') unless @scanner.scan(')')

        nil
      end
    end
  end
end
