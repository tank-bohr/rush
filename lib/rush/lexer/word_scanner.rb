# typed: true
# frozen_string_literal: true

require 'strscan'

module Rush
  class Lexer
    # Scans one word from the shared StringScanner into an AST::Word of typed
    # segments: literal runs (quote-removed, with a `quoted` flag) and :param
    # segments for $name / ${...}. Handles the three quoting forms; command
    # substitution and arithmetic arrive in later slices.
    class WordScanner
      extend T::Sig
      include ScannerPredicates

      TERMINATOR = /[ \t\n;&|<>()]/
      DISPATCH = {
        "'" => :single_quote, '"' => :double_quote, '\\' => :escape,
        '$' => :dollar, '`' => :backtick
      }.freeze

      # Scan the next shell word from a live lexer scanner, stopping at the first
      # unquoted terminator (blank / operator). `interactive` mirrors the lexer:
      # an accumulating parse may ask for more input, the final one may not.
      sig { params(scanner: StringScanner, interactive: T::Boolean).returns(AST::Word) }
      def self.next_word(scanner, interactive:)
        new(scanner, terminator: TERMINATOR, interactive: interactive).scan
      end

      # Scan a complete, already-delimited string (a ${...} operator word or
      # arithmetic source) as one word: no terminators apply (blanks/operators
      # are literal), only quote / $ / ` stay special.
      sig { params(text: String).returns(AST::Word) }
      def self.entire(text)
        new(StringScanner.new(text), terminator: nil, interactive: false).scan
      end

      # terminator: the character class that ends a word, or nil in whole mode.
      sig { params(scanner: StringScanner, terminator: T.nilable(Regexp), interactive: T::Boolean).void }
      def initialize(scanner, terminator:, interactive:)
        @scanner = scanner
        @terminator = terminator
        @interactive = interactive
        @buffer = SegmentBuffer.new
      end

      sig { returns(AST::Word) }
      def scan
        loop do
          char = @scanner.getch or return @buffer.word
          return rewind_then_build if terminates?(char)

          step(char)
        end
      end

      private

      sig { params(char: String).returns(T::Boolean) }
      def terminates?(char)
        terminator = @terminator
        terminator ? char.match?(terminator) : false
      end

      sig { returns(AST::Word) }
      def rewind_then_build
        @scanner.unscan
        @buffer.word
      end

      sig { params(char: String).void }
      def step(char)
        handler = DISPATCH.fetch(char, nil)
        handler ? send(handler) : (@buffer << char)
      end

      sig { void }
      def single_quote
        content = @scanner.scan(/[^']*/)
        raise IncompleteInput, 'unterminated single quote' unless @scanner.scan("'")

        push(content, quoted: true)
      end

      sig { void }
      def double_quote
        DoubleQuoteScanner.new(@scanner, @buffer, -> { continuation }).scan
      end

      # Line continuation (POSIX 2.2.1): the backslash-newline pair vanishes.
      # When the newline ends an accumulating (interactive) buffer, the logical
      # line continues on input the lexer does not have yet, so ask the reader
      # for the next line. The final parse at end of input — and `entire` mode,
      # whose text is already complete — just drops the pair, like dash.
      sig { void }
      def continuation
        @scanner.skip(/\n/)
        raise IncompleteInput, 'line continuation' if @interactive && @terminator && @scanner.eos?
      end

      # A lone `$` that begins no valid reference stays a literal dollar: merged
      # into the current literal run when bare, a quoted literal segment in "...".
      sig { void }
      def dollar
        @scanner.unscan
        segment = DollarScanner.new(@scanner).read(quoted: false)
        segment ? @buffer.push(segment) : (@buffer << '$')
      end

      sig { void }
      def backtick
        @scanner.unscan
        @buffer.push(DollarScanner.new(@scanner).read_backtick(quoted: false))
      end

      sig { void }
      def escape
        char = @scanner.getch or return trailing_backslash
        char == "\n" ? continuation : push(char, quoted: true)
      end

      # A backslash that ends the input stays literal, like dash.
      sig { void }
      def trailing_backslash
        @buffer << '\\'
      end

      sig { params(value: T.untyped, quoted: T::Boolean).void }
      def push(value, quoted:)
        @buffer.push(AST::LiteralSegment.new(value, quoted))
      end
    end
  end
end
