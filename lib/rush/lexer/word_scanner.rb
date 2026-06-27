# frozen_string_literal: true

module Rush
  class Lexer
    # Scans one word from the shared StringScanner into an AST::Word of typed
    # segments, handling the three POSIX quoting forms (single quotes, double
    # quotes, backslash). Quote characters are removed; each run records whether
    # it was quoted. $-expansions and backticks are added in later slices.
    class WordScanner
      TERMINATOR = /[ \t\n;&|<>]/
      LITERAL_RUN = /[^'"\\ \t\n;&|<>]+/
      DOUBLE_SPECIAL = ['"', '\\', '$', '`'].freeze
      DISPATCH = { "'" => :single_quote, '"' => :double_quote, '\\' => :escape }.freeze

      def initialize(scanner)
        @scanner = scanner
        @segments = []
        @literal = +''
      end

      def scan
        step until ended?
        flush
        AST::Word.new(@segments)
      end

      private

      def ended? = @scanner.eos? || @scanner.peek(1).match?(TERMINATOR)

      def step
        handler = DISPATCH[@scanner.peek(1)]
        handler ? send(handler) : (@literal << @scanner.scan(LITERAL_RUN))
      end

      def single_quote
        @scanner.getch
        content = @scanner.scan(/[^']*/)
        raise ParseError, 'unterminated single quote' unless @scanner.scan("'")

        push(content, quoted: true)
      end

      def double_quote
        @scanner.getch
        push(read_double, quoted: true)
      end

      def read_double
        content = +''
        content << double_char until at_double_end?
        raise ParseError, 'unterminated double quote' if @scanner.eos?

        @scanner.getch.then { content }
      end

      def at_double_end? = @scanner.eos? || @scanner.peek(1) == '"'

      def double_char
        @scanner.peek(1) == '\\' ? double_escape : @scanner.getch
      end

      def double_escape
        @scanner.getch
        DOUBLE_SPECIAL.include?(@scanner.peek(1)) ? @scanner.getch : "\\#{@scanner.getch}"
      end

      def escape
        @scanner.getch
        char = @scanner.getch
        push(char, quoted: true) unless char.nil? || char == "\n"
      end

      def push(value, quoted:)
        flush
        @segments << AST::WordSegment.new(kind: :literal, value: value, quoted: quoted)
      end

      def flush
        return if @literal.empty?

        @segments << AST::WordSegment.new(kind: :literal, value: @literal, quoted: false)
        @literal = +''
      end
    end
  end
end
