# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Reads a substitution at the word scanner's current position into the matching
    # AST segment: $name / ${...} parameter refs (via ParamScanner), $(...) command
    # substitution, $((...)) arithmetic, and `...` backticks. #read returns nil for
    # a lone `$` that begins no valid reference, so the caller keeps it as a
    # literal dollar.
    class DollarScanner
      extend T::Sig
      include ScannerPredicates

      sig { params(scanner: StringScanner).void }
      def initialize(scanner)
        @scanner = scanner
      end

      # The segment for a `$...` at the scanner head (the `$` not yet consumed),
      # or nil when no valid reference follows. An unterminated ${ asks for more
      # input: an interactive word may continue on the next line.
      sig { params(quoted: T::Boolean).returns(T.untyped) }
      def read(quoted:)
        @scanner.getch
        return dollar_paren(quoted) if peek?('(')

        ref = ParamScanner.new(@scanner, error: IncompleteInput).read
        ref && AST::ParamSegment.new(ref, quoted)
      end

      # The command segment for a `` `...` `` at the scanner head.
      sig { params(quoted: T::Boolean).returns(AST::CommandSegment) }
      def read_backtick(quoted:)
        @scanner.getch # `
        AST::CommandSegment.new(SubstitutionReader.new(@scanner).backticks, quoted)
      end

      private

      # `$((` begins arithmetic; a lone `$(` (including `$( (`) is command sub.
      sig { params(quoted: T::Boolean).returns(AST::DynamicSegment[String]) }
      def dollar_paren(quoted)
        @scanner.getch # opening (
        reader = SubstitutionReader.new(@scanner)
        return AST::CommandSegment.new(reader.parens, quoted) unless peek?('(')

        @scanner.getch # second (
        AST::ArithSegment.new(reader.arithmetic, quoted)
      end
    end
  end
end
