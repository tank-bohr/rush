# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Reads the parameter reference after a consumed `$` at the scanner head:
    # $name / $digit / $special, or the braced ${...} forms. Returns nil when no
    # reference begins, so the caller keeps the `$` literal. An unterminated ${
    # raises the given error class: IncompleteInput lets an interactive word ask
    # for another line, while heredoc bodies and prompt values are already
    # complete and fail as plain parse errors.
    class ParamScanner
      extend T::Sig

      PARAM = /[a-zA-Z_]\w*|\d|[@*#?$!\-0]/

      sig { params(scanner: StringScanner, error: T.class_of(ParseError)).void }
      def initialize(scanner, error: ParseError)
        @scanner = scanner
        @error = error
      end

      sig { returns(T.nilable(AST::ParamRef)) }
      def read
        return braced if @scanner.peek(1) == '{'

        name = @scanner.scan(PARAM)
        name && AST::ParamRef.simple(name)
      end

      private

      sig { returns(AST::ParamRef) }
      def braced
        @scanner.getch
        body = @scanner.scan(/[^}]*/) || ''
        raise @error, 'unterminated ${' unless @scanner.scan('}')

        AST::ParamRef.parse(body)
      end
    end
  end
end
