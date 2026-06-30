# typed: true
# frozen_string_literal: true

require 'strscan'

module Rush
  class Lexer
    # Scans one word from the shared StringScanner into an AST::Word of typed
    # segments: literal runs (quote-removed, with a `quoted` flag) and :param
    # segments for $name / ${...}. Handles the three quoting forms; command
    # substitution and arithmetic arrive in later slices.
    class WordScanner # rubocop:disable Metrics/ClassLength
      extend T::Sig

      TERMINATOR = /[ \t\n;&|<>()]/
      LITERAL_RUN = /[^'"\\$` \t\n;&|<>()]+/
      WHOLE_LITERAL = /[^'"\\$`]+/ # operator-word mode: only quotes / $ / ` are special
      DOUBLE_LITERAL = /[^"$\\`]+/
      DOUBLE_SPECIAL = ['"', '\\', '$', '`'].freeze
      DISPATCH = {
        "'" => :single_quote, '"' => :double_quote, '\\' => :escape,
        '$' => :dollar, '`' => :backtick
      }.freeze

      # Scan the next shell word from a live lexer scanner, stopping at the first
      # unquoted terminator (blank / operator).
      sig { params(scanner: StringScanner).returns(AST::Word) }
      def self.next_word(scanner)
        new(scanner).scan
      end

      # Scan a complete, already-delimited string (a ${...} operator word or
      # arithmetic source) as one word: no terminators apply (blanks/operators
      # are literal), only quote / $ / ` stay special.
      sig { params(text: String).returns(AST::Word) }
      def self.entire(text)
        new(StringScanner.new(text), terminator: nil).scan
      end

      # terminator: the character class that ends a word, or nil in whole mode.
      sig { params(scanner: StringScanner, terminator: T.nilable(Regexp)).void }
      def initialize(scanner, terminator: TERMINATOR)
        @scanner = scanner
        @terminator = terminator
        @segments = []
        @literal = +''
      end

      sig { returns(AST::Word) }
      def scan
        step until ended?
        flush
        AST::Word.new(@segments)
      end

      private

      sig { returns(T::Boolean) }
      def ended?
        @scanner.eos? || (@terminator ? @scanner.peek(1).match?(@terminator) : false)
      end

      sig { void }
      def step
        handler = DISPATCH[@scanner.peek(1)]
        handler ? send(handler) : (@literal << @scanner.scan(literal_pattern).to_s)
      end

      sig { returns(Regexp) }
      def literal_pattern
        @terminator ? LITERAL_RUN : WHOLE_LITERAL
      end

      sig { void }
      def single_quote
        @scanner.getch
        content = @scanner.scan(/[^']*/)
        raise IncompleteInput, 'unterminated single quote' unless @scanner.scan("'")

        push(content, quoted: true)
      end

      sig { void }
      def double_quote
        @scanner.getch
        push('', quoted: true) if @scanner.peek(1) == '"' # "" yields one empty field
        double_step until end_double?
        raise IncompleteInput, 'unterminated double quote' if @scanner.eos?

        @scanner.getch
      end

      sig { returns(T::Boolean) }
      def end_double?
        @scanner.eos? || @scanner.peek(1) == '"'
      end

      sig { void }
      def double_step
        char = @scanner.peek(1)
        return double_dollar if char == '$'
        return add(DollarScanner.new(@scanner).read_backtick(quoted: true)) if char == '`'
        return double_escape if char == '\\'

        push(@scanner.scan(DOUBLE_LITERAL), quoted: true)
      end

      sig { void }
      def double_escape
        @scanner.getch
        DOUBLE_SPECIAL.include?(@scanner.peek(1)) ? push(@scanner.getch, quoted: true) : push('\\', quoted: true)
      end

      # A lone `$` that begins no valid reference stays a literal dollar: merged
      # into the current literal run when bare, a quoted literal segment in "...".
      sig { void }
      def dollar
        segment = DollarScanner.new(@scanner).read(quoted: false)
        segment ? add(segment) : (@literal << '$')
      end

      sig { void }
      def double_dollar
        segment = DollarScanner.new(@scanner).read(quoted: true)
        segment ? add(segment) : push('$', quoted: true)
      end

      sig { void }
      def backtick
        add(DollarScanner.new(@scanner).read_backtick(quoted: false))
      end

      sig { void }
      def escape
        @scanner.getch
        char = @scanner.getch
        push(char, quoted: true) if char && char != "\n"
      end

      sig { params(value: T.untyped, quoted: T::Boolean).void }
      def push(value, quoted:)
        add(AST::LiteralSegment.new(value, quoted))
      end

      sig { params(segment: T.untyped).void }
      def add(segment)
        flush
        @segments << segment
      end

      sig { void }
      def flush
        return if @literal.empty?

        @segments << AST::LiteralSegment.new(@literal, false)
        @literal = +''
      end
    end
  end
end
