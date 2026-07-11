# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Reads the body of a ${...} after the consumed `${`, up to the matching
    # `}` (POSIX 2.6.2): a nested `${` opens a level (read recursively), a
    # backslash escapes the next character, and quoted strings / command and
    # arithmetic substitutions are skipped whole. `quoted` follows dash: inside
    # double quotes and here-doc bodies a single quote is an ordinary
    # character; outside them it quotes a region. The body keeps its raw
    # spelling — the operator word is re-scanned at expansion time.
    class BracedReader
      extend T::Sig
      include QuoteSkips

      # The literal run per context: a quoted ${...} keeps ' ordinary.
      PLAIN = { false => /[^}$\\'"`]+/, true => /[^}$\\"`]+/ }.freeze

      sig { params(scanner: StringScanner, error: T.class_of(ParseError), quoted: T::Boolean).void }
      def initialize(scanner, error:, quoted:)
        @scanner = scanner
        @error = error
        @quoted = quoted
      end

      sig { returns(String) }
      def read
        body = +''
        body << step until peek?('}')
        @scanner.getch
        body
      end

      private

      sig { returns(String) }
      def step
        @scanner.scan(PLAIN.fetch(@quoted)) || special
      end

      sig { returns(String) }
      def special
        return "\\#{must_char}" if @scanner.scan('\\')
        return single if @scanner.scan("'")
        return double if @scanner.scan('"')
        return "`#{SubstitutionReader.new(@scanner).backticks}`" if @scanner.scan('`')

        dollar
      end

      # The unterminated-input error the call site configured.
      sig { override.returns(T.class_of(ParseError)) }
      def error_class
        @error
      end

      # The only characters that reach here are `$` and end of input. After a
      # live `$`: `${` opens a nested reference, `$(` a substitution; a `$`
      # that begins neither stays literal (its name is a plain run).
      sig { returns(String) }
      def dollar
        raise @error, 'unterminated ${' unless @scanner.scan('$')
        return "${#{nested}}" if @scanner.scan('{')
        return '$' unless @scanner.scan('(')

        substitution
      end

      sig { returns(String) }
      def nested
        BracedReader.new(@scanner, error: @error, quoted: @quoted).read
      end

      # `$((` is arithmetic, a lone `$(` is command substitution (as
      # DollarScanner disambiguates).
      sig { returns(String) }
      def substitution
        reader = SubstitutionReader.new(@scanner)
        return "$(#{reader.parens})" unless @scanner.scan('(')

        "$((#{reader.arithmetic}))"
      end
    end
  end
end
