# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Quote-region skipping shared by the readers that must find a closing
    # delimiter in raw source (BracedReader's `}`, ParenReader's `)`). Each
    # helper consumes one region after its opening character and returns it
    # with its delimiters, so the body keeps its raw spelling; a backslash
    # always protects exactly the next character. Includers provide @scanner
    # and may override #error_class to raise their configured error.
    module QuoteSkips
      extend T::Sig
      include Kernel
      include ScannerPredicates

      private

      # The error for unterminated input; an unfinished region can continue
      # on the next interactive line.
      sig { overridable.returns(T.class_of(ParseError)) }
      def error_class
        IncompleteInput
      end

      sig { returns(String) }
      def must_char
        @scanner.getch || raise(error_class, 'unterminated escape')
      end

      sig { returns(String) }
      def single
        body = @scanner.scan(/[^']*/)
        raise error_class, 'unterminated single quote' unless @scanner.scan("'")

        "'#{body}'"
      end

      sig { returns(String) }
      def double
        body = +'"'
        body << double_chunk until peek?('"')
        @scanner.getch
        body << '"'
      end

      sig { returns(String) }
      def double_chunk
        @scanner.scan(/[^"\\$`]+/) || double_special
      end

      # `\`, `$` and backticks stay live inside double quotes: an embedded
      # $( ... ) or ${ ... } is skipped whole, so its `)` and `}` never count.
      sig { returns(String) }
      def double_special
        return "\\#{must_char}" if @scanner.scan('\\')
        return "`#{SubstitutionReader.new(@scanner).backticks}`" if @scanner.scan('`')

        double_dollar
      end

      sig { returns(String) }
      def double_dollar
        raise error_class, 'unterminated double quote' unless @scanner.scan('$')
        return "${#{quoted_braced}}" if @scanner.scan('{')
        return '$' unless @scanner.scan('(')

        "$(#{SubstitutionReader.new(@scanner).parens})"
      end

      sig { returns(String) }
      def quoted_braced
        BracedReader.new(@scanner, error: error_class, quoted: true).read
      end
    end
  end
end
