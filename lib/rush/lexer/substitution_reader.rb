# frozen_string_literal: true

module Rush
  class Lexer
    # Reads the raw body of a command substitution from the shared scanner:
    # $( ... ) with balanced parentheses, or ` ... ` up to the next backtick.
    # The body is re-parsed and executed at expansion time.
    class SubstitutionReader
      def initialize(scanner)
        @scanner = scanner
      end

      def parens
        @depth = 1
        (+'').tap { |body| body << paren_char until @depth.zero? }
      end

      def backticks
        body = @scanner.scan(/[^`]*/)
        raise IncompleteInput, 'unterminated `' unless @scanner.scan('`')

        body
      end

      private

      def paren_char
        raise IncompleteInput, 'unterminated $(' if @scanner.eos?

        char = @scanner.getch
        adjust(char)
        @depth.zero? ? '' : char
      end

      def adjust(char)
        @depth += 1 if char == '('
        @depth -= 1 if char == ')'
      end
    end
  end
end
