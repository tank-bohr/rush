# frozen_string_literal: true

module Rush
  class Lexer
    # Scans one word from the shared StringScanner into an AST::Word. Slice 1
    # produces a single :literal segment (quoting, $-expansions, backticks and
    # tildes are added in later slices, each pushing its own typed segment). The
    # word ends at an unquoted blank, newline or operator character.
    class WordScanner
      WORD = /[^ \t\n;&|<>]+/

      def initialize(scanner)
        @scanner = scanner
      end

      def scan = AST::Word.literal(@scanner.scan(WORD))
    end
  end
end
