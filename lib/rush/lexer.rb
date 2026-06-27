# frozen_string_literal: true

require 'strscan'

module Rush
  # Phase 0 lexer: a StringScanner pump that yields [symbol, value] pairs for
  # racc. It skips blanks and comments, then emits NEWLINE, ';' or a literal
  # WORD. The context-sensitive POSIX Grammar Rules 1-9, quoting and here-docs
  # arrive with the real lexer in Phase 1.
  class Lexer
    BLANK = /[ \t]+/
    COMMENT = /#[^\n]*/
    WORD = /[^ \t\n;#]+/

    def initialize(source)
      @scanner = StringScanner.new(source)
    end

    def location = @scanner.charpos

    def next_token
      skip_insignificant
      return [false, false] if @scanner.eos?

      scan_token
    end

    private

    def skip_insignificant
      loop { break unless @scanner.skip(BLANK) || @scanner.skip(COMMENT) }
    end

    def scan_token
      return [:NEWLINE, "\n"] if @scanner.scan("\n")
      return [';', ';'] if @scanner.scan(';')

      [:WORD, AST::Word.literal(@scanner.scan(WORD))]
    end
  end
end
