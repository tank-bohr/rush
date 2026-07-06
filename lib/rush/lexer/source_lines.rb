# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Tracks source line numbers for tokens produced from a StringScanner. The
    # lexer itself owns tokenization; this helper only maps consumed scanner text
    # to absolute source lines.
    class SourceLines
      extend T::Sig

      sig { params(scanner: StringScanner, offset: Integer).void }
      def initialize(scanner, offset)
        @scanner = scanner
        @line = offset + 1
      end

      sig { params(blk: T.proc.returns(AST::Word)).returns(AST::Word) }
      def word(&blk)
        line = @line
        start = @scanner.pos
        yield.tap { count_newlines_since(start) }.then { |word| AST::Word.new(word.segments, source_line: line) }
      end

      sig { params(start: Integer).void }
      def heredoc_newline(start)
        @line += consumed_since(start).count("\n") + 1
      end

      private

      sig { params(start: Integer).void }
      def count_newlines_since(start)
        @line += consumed_since(start).count("\n")
      end

      sig { params(start: Integer).returns(String) }
      def consumed_since(start)
        @scanner.string[start...@scanner.pos].to_s
      end
    end
  end
end
