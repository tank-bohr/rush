# frozen_string_literal: true

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
      DOUBLE_LITERAL = /[^"$\\]+/
      DOUBLE_SPECIAL = ['"', '\\', '$', '`'].freeze
      SIMPLE_PARAM = /[a-zA-Z_]\w*|\d|[@*#?$!\-0]/
      DISPATCH = {
        "'" => :single_quote, '"' => :double_quote, '\\' => :escape,
        '$' => :dollar, '`' => :backtick
      }.freeze

      # whole: scan the entire input as one word's content (no blank/operator
      # terminators) — used for already-delimited ${} operator words.
      def initialize(scanner, whole: false)
        @scanner = scanner
        @whole = whole
        @segments = []
        @literal = +''
      end

      def scan
        step until ended?
        flush
        AST::Word.new(@segments)
      end

      private

      def ended? = @scanner.eos? || (!@whole && @scanner.peek(1).match?(TERMINATOR))

      def step
        handler = DISPATCH[@scanner.peek(1)]
        handler ? send(handler) : (@literal << @scanner.scan(literal_pattern))
      end

      def literal_pattern = @whole ? WHOLE_LITERAL : LITERAL_RUN

      def single_quote
        @scanner.getch
        content = @scanner.scan(/[^']*/)
        raise ParseError, 'unterminated single quote' unless @scanner.scan("'")

        push(content, quoted: true)
      end

      def double_quote
        @scanner.getch
        push('', quoted: true) if @scanner.peek(1) == '"' # "" yields one empty field
        double_step until end_double?
        raise ParseError, 'unterminated double quote' if @scanner.eos?

        @scanner.getch
      end

      def end_double? = @scanner.eos? || @scanner.peek(1) == '"'

      def double_step
        char = @scanner.peek(1)
        return read_dollar(quoted: true) if char == '$'
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
        return command_sub(quoted) if @scanner.peek(1) == '('

        ref = read_param_ref
        ref ? push_param(ref, quoted: quoted) : push_literal('$', quoted)
      end

      def command_sub(quoted)
        @scanner.getch # (
        push_command(SubstitutionReader.new(@scanner).parens, quoted: quoted)
      end

      def backtick
        @scanner.getch # `
        push_command(SubstitutionReader.new(@scanner).backticks, quoted: false)
      end

      def read_param_ref
        return braced_ref if @scanner.peek(1) == '{'

        name = @scanner.scan(SIMPLE_PARAM)
        name && AST::ParamRef.simple(name)
      end

      def braced_ref
        @scanner.getch
        body = @scanner.scan(/[^}]*/)
        raise ParseError, 'unterminated ${' unless @scanner.scan('}')

        AST::ParamRef.parse(body)
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

      def push_param(ref, quoted:)
        flush
        @segments << AST::WordSegment.new(kind: :param, value: ref, quoted: quoted)
      end

      def push_command(source, quoted:)
        flush
        @segments << AST::WordSegment.new(kind: :command, value: source, quoted: quoted)
      end

      def push_literal(text, quoted)
        quoted ? push(text, quoted: true) : (@literal << text)
      end

      def flush
        return if @literal.empty?

        @segments << AST::WordSegment.new(kind: :literal, value: @literal, quoted: false)
        @literal = +''
      end
    end
  end
end
