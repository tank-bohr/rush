# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Reads the parameter reference after a consumed `$` at the scanner head:
    # $name / $digit / $special, or the braced ${...} forms (whose body the
    # BracedReader matches to the closing brace). Returns nil when no reference
    # begins, so the caller keeps the `$` literal. An unterminated ${ raises
    # the given error class: IncompleteInput lets an interactive word ask for
    # another line, while heredoc bodies and prompt values are already complete
    # and fail as plain parse errors. `quoted` names the surrounding context —
    # inside double quotes and here-doc bodies a single quote is ordinary.
    class ParamScanner
      extend T::Sig

      PARAM = /[a-zA-Z_]\w*|\d|[@*#?$!\-0]/

      sig { params(scanner: StringScanner, quoted: T::Boolean, error: T.class_of(ParseError)).void }
      def initialize(scanner, quoted:, error: ParseError)
        @scanner = scanner
        @error = error
        @quoted = quoted
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
        AST::ParamRef.parse(BracedReader.new(@scanner, error: @error, quoted: @quoted).read)
      end
    end
  end
end
