# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Reads the body of a $( ... ) after the consumed `$(`, up to the closing
    # `)` (POSIX 2.6.3: any valid shell script may appear inside). Plain
    # parentheses nest; quoted strings, backslash escapes, backticks, ${...}
    # references and `#` comments are skipped whole (ParenRegions); and a
    # `case` pattern's unbalanced `)` (CaseTracker) does not count. The body
    # keeps its raw spelling — it is re-parsed at expansion time.
    class ParenReader
      extend T::Sig
      include ParenRegions

      # The longest run with no syntactic weight for paren matching.
      PLAIN = /[^\s()'"\\`;&|<>#$]+/

      # Which CaseTracker event each operator character raises.
      OPERATORS = {
        '&' => :separator, '|' => :separator, "\n" => :newline,
        '<' => :redirect, '>' => :redirect
      }.freeze

      sig { params(scanner: StringScanner).void }
      def initialize(scanner)
        @scanner = scanner
        @tracker = T.let(CaseTracker.new, CaseTracker)
        @word_start = T.let(true, T::Boolean)
      end

      sig { returns(String) }
      def read
        body = +''
        body << step while @tracker.open?
        body
      end

      private

      sig { returns(String) }
      def step
        blank || word || region || punct || closer
      end

      sig { returns(T.nilable(String)) }
      def blank
        text = @scanner.scan(/[^\S\n]+/)
        @word_start = true if text
        text
      end

      sig { returns(T.nilable(String)) }
      def word
        text = @scanner.scan(PLAIN)
        return unless text

        @tracker.word(@word_start ? text : '')
        @word_start = false
        text
      end

      sig { returns(T.nilable(String)) }
      def punct
        semi || operator || open_paren
      end

      sig { returns(T.nilable(String)) }
      def semi
        return unless @scanner.scan(';')

        @word_start = true
        return dsemi if @scanner.scan(';')

        @tracker.separator
        ';'
      end

      sig { returns(String) }
      def dsemi
        @tracker.dsemi
        ';;'
      end

      sig { returns(T.nilable(String)) }
      def operator
        char = @scanner.scan(/[&|<>\n]/)
        return unless char

        @tracker.public_send(OPERATORS.fetch(char))
        @word_start = true
        char
      end

      sig { returns(T.nilable(String)) }
      def open_paren
        return unless @scanner.scan('(')

        @tracker.open_paren
        @word_start = true
        '('
      end

      sig { returns(String) }
      def closer
        raise IncompleteInput, 'unterminated $(' unless @scanner.scan(')')

        @word_start = true
        @tracker.close_paren? ? ')' : ''
      end
    end
  end
end
