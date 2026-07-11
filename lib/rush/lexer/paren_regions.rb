# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # The skip-whole regions of a $( ... ) body (ParenReader's mixin): quoted
    # strings, backslash escapes, backticks, ${...} references, and `#`
    # comments. A region reads as one ordinary — never keyword — word to the
    # CaseTracker, and its text returns with the delimiters so the body keeps
    # its raw spelling for the expansion-time re-parse.
    module ParenRegions
      extend T::Sig
      include QuoteSkips

      private

      sig { returns(T.nilable(String)) }
      def region
        squote || dquote || backtick || escape || dollar || comment
      end

      sig { returns(T.nilable(String)) }
      def squote
        skipped(single) if @scanner.scan("'")
      end

      sig { returns(T.nilable(String)) }
      def dquote
        skipped(double) if @scanner.scan('"')
      end

      sig { returns(T.nilable(String)) }
      def backtick
        skipped("`#{SubstitutionReader.new(@scanner).backticks}`") if @scanner.scan('`')
      end

      sig { returns(T.nilable(String)) }
      def escape
        skipped("\\#{must_char}") if @scanner.scan('\\')
      end

      sig { returns(T.nilable(String)) }
      def dollar
        return unless @scanner.scan('$')
        return skipped('$') unless @scanner.scan('{')

        skipped("${#{braced}}")
      end

      sig { returns(String) }
      def braced
        BracedReader.new(@scanner, error: IncompleteInput, quoted: false).read
      end

      # A `#` at the start of a word begins a comment running to the line
      # end (kept raw, so a `)` inside it does not count); mid-word it is an
      # ordinary character.
      sig { returns(T.nilable(String)) }
      def comment
        return unless peek?('#')
        return skipped(must_char) unless @word_start

        @scanner.scan(/#[^\n]*/)
      end

      sig { params(text: String).returns(String) }
      def skipped(text)
        @tracker.word('')
        @word_start = false
        text
      end
    end
  end
end
