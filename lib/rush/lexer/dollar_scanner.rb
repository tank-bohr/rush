# frozen_string_literal: true

module Rush
  class Lexer
    # Reads a substitution at the word scanner's current position into the matching
    # AST segment: $name / ${...} parameter refs, $(...) command substitution,
    # $((...)) arithmetic, and `...` backticks. #read returns nil for a lone `$`
    # that begins no valid reference, so the caller keeps it as a literal dollar.
    class DollarScanner
      SIMPLE_PARAM = /[a-zA-Z_]\w*|\d|[@*#?$!\-0]/

      def initialize(scanner)
        @scanner = scanner
      end

      # The segment for a `$...` at the scanner head (the `$` not yet consumed),
      # or nil when no valid reference follows.
      def read(quoted:)
        @scanner.getch
        return dollar_paren(quoted) if @scanner.peek(1) == '('

        ref = read_param_ref
        ref && AST::ParamSegment.new(ref, quoted)
      end

      # The command segment for a `` `...` `` at the scanner head.
      def read_backtick(quoted:)
        @scanner.getch # `
        AST::CommandSegment.new(SubstitutionReader.new(@scanner).backticks, quoted)
      end

      private

      # `$((` begins arithmetic; a lone `$(` (including `$( (`) is command sub.
      def dollar_paren(quoted)
        @scanner.getch # opening (
        reader = SubstitutionReader.new(@scanner)
        return AST::CommandSegment.new(reader.parens, quoted) unless @scanner.peek(1) == '('

        @scanner.getch # second (
        AST::ArithSegment.new(reader.arithmetic, quoted)
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
    end
  end
end
