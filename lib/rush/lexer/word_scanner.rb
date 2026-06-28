# frozen_string_literal: true

require 'strscan'

module Rush
  class Lexer
    # Scans one word from the shared StringScanner into an AST::Word of typed
    # segments: literal runs (quote-removed, with a `quoted` flag) and :param
    # segments for $name / ${...}. Handles the three quoting forms; command
    # substitution and arithmetic arrive in later slices.
    class WordScanner
      TERMINATOR = /[ \t\n;&|<>()]/
      LITERAL_RUN = /[^'"\\$` \t\n;&|<>()]+/
      WHOLE_LITERAL = /[^'"\\$`]+/ # operator-word mode: only quotes / $ / ` are special
      DOUBLE_LITERAL = /[^"$\\`]+/
      DOUBLE_SPECIAL = ['"', '\\', '$', '`'].freeze
      SIMPLE_PARAM = /[a-zA-Z_]\w*|\d|[@*#?$!\-0]/
      DISPATCH = {
        "'" => :single_quote, '"' => :double_quote, '\\' => :escape,
        '$' => :dollar, '`' => :backtick
      }.freeze

      # Scan the next shell word from a live lexer scanner, stopping at the first
      # unquoted terminator (blank / operator).
      def self.next_word(scanner) = new(scanner).scan

      # Scan a complete, already-delimited string (a ${...} operator word or
      # arithmetic source) as one word: no terminators apply (blanks/operators
      # are literal), only quote / $ / ` stay special.
      def self.entire(text) = new(StringScanner.new(text), terminator: nil).scan

      # terminator: the character class that ends a word, or nil in whole mode.
      def initialize(scanner, terminator: TERMINATOR)
        @scanner = scanner
        @terminator = terminator
        @segments = []
        @literal = +''
      end

      def scan
        step until ended?
        flush
        AST::Word.new(@segments)
      end

      private

      def ended? = @scanner.eos? || (!@terminator.nil? && @scanner.peek(1).match?(@terminator))

      def step
        handler = DISPATCH[@scanner.peek(1)]
        handler ? send(handler) : (@literal << @scanner.scan(literal_pattern))
      end

      def literal_pattern = @terminator.nil? ? WHOLE_LITERAL : LITERAL_RUN

      def single_quote
        @scanner.getch
        content = @scanner.scan(/[^']*/)
        raise IncompleteInput, 'unterminated single quote' unless @scanner.scan("'")

        push(content, quoted: true)
      end

      def double_quote
        @scanner.getch
        push('', quoted: true) if @scanner.peek(1) == '"' # "" yields one empty field
        double_step until end_double?
        raise IncompleteInput, 'unterminated double quote' if @scanner.eos?

        @scanner.getch
      end

      def end_double? = @scanner.eos? || @scanner.peek(1) == '"'

      def double_step
        char = @scanner.peek(1)
        return read_dollar(quoted: true) if char == '$'
        return read_backtick(quoted: true) if char == '`'
        return double_escape if char == '\\'

        push(@scanner.scan(DOUBLE_LITERAL), quoted: true)
      end

      def double_escape
        @scanner.getch
        DOUBLE_SPECIAL.include?(@scanner.peek(1)) ? push(@scanner.getch, quoted: true) : push('\\', quoted: true)
      end

      def dollar = read_dollar(quoted: false)

      def read_dollar(quoted:)
        @scanner.getch
        return dollar_paren(quoted) if @scanner.peek(1) == '('

        ref = read_param_ref
        return add(:param, ref, quoted) if ref

        quoted ? push('$', quoted: true) : (@literal << '$')
      end

      # `$((` begins arithmetic; a lone `$(` (including `$( (`) is command sub.
      def dollar_paren(quoted)
        @scanner.getch # opening (
        return add(:command, SubstitutionReader.new(@scanner).parens, quoted) unless @scanner.peek(1) == '('

        @scanner.getch # second (
        add(:arith, SubstitutionReader.new(@scanner).arithmetic, quoted)
      end

      def backtick = read_backtick(quoted: false)

      def read_backtick(quoted:)
        @scanner.getch # `
        add(:command, SubstitutionReader.new(@scanner).backticks, quoted)
      end

      def read_param_ref
        return braced_ref if @scanner.peek(1) == '{'

        name = @scanner.scan(SIMPLE_PARAM)
        name && AST::ParamRef.simple(name)
      end

      def braced_ref
        @scanner.getch
        body = @scanner.scan(/[^}]*/)
        raise IncompleteInput, 'unterminated ${' unless @scanner.scan('}')

        AST::ParamRef.parse(body)
      end

      def escape
        @scanner.getch
        char = @scanner.getch
        push(char, quoted: true) unless char.nil? || char == "\n"
      end

      def push(value, quoted:) = add(:literal, value, quoted)

      def add(kind, value, quoted)
        flush
        @segments << AST::WordSegment.new(kind: kind, value: value, quoted: quoted)
      end

      def flush
        return if @literal.empty?

        @segments << AST::WordSegment.new(kind: :literal, value: @literal, quoted: false)
        @literal = +''
      end
    end
  end
end
