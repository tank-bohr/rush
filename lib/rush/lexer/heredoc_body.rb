# frozen_string_literal: true

module Rush
  class Lexer
    # Scans an unquoted here-document body into an AST::Word of literal / :param /
    # :command segments. Unlike WordScanner there are no quote delimiters (quotes
    # are literal) and no terminator (it consumes the whole body); a backslash
    # escapes only $, ` and \. Expansion itself is deferred to execution, so the
    # body reflects the variable values at the time the command runs. (Shares the
    # $-and-backtick shape with WordScanner; a common extractor can wait until the
    # Phase 2 ${} forms land.)
    class HeredocBody
      RUN = /[^$\\`]+/
      PARAM = /[a-zA-Z_]\w*|\d|[@*#?$!\-0]/
      ESCAPABLE = ['$', '`', '\\'].freeze

      def initialize(text)
        @scanner = StringScanner.new(text)
        @segments = []
        @literal = +''
      end

      def scan
        step until @scanner.eos?
        flush
        AST::Word.new(@segments)
      end

      private

      def step
        char = @scanner.peek(1)
        return dollar if char == '$'
        return backtick if char == '`'
        return escape if char == '\\'

        @literal << @scanner.scan(RUN)
      end

      def dollar
        @scanner.getch
        @scanner.peek(1) == '(' ? command_sub : param
      end

      def command_sub
        @scanner.getch
        push(AST::CommandSegment.new(SubstitutionReader.new(@scanner).parens, false))
      end

      def backtick
        @scanner.getch
        push(AST::CommandSegment.new(SubstitutionReader.new(@scanner).backticks, false))
      end

      def param
        ref = read_ref
        ref ? push(AST::ParamSegment.new(ref, false)) : (@literal << '$')
      end

      def read_ref
        return braced if @scanner.peek(1) == '{'

        name = @scanner.scan(PARAM)
        name && AST::ParamRef.simple(name)
      end

      def braced
        @scanner.getch
        body = @scanner.scan(/[^}]*/)
        raise ParseError, 'unterminated ${' unless @scanner.scan('}')

        AST::ParamRef.parse(body)
      end

      def escape
        @scanner.getch
        char = @scanner.getch
        @literal << (ESCAPABLE.include?(char) ? char : "\\#{char}")
      end

      def push(segment)
        flush
        @segments << segment
      end

      def flush
        return if @literal.empty?

        @segments << AST::LiteralSegment.new(@literal, false)
        @literal = +''
      end
    end
  end
end
