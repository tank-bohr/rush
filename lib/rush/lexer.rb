# frozen_string_literal: true

require 'strscan'
require_relative 'lexer/operator_table'
require_relative 'lexer/lex_state'
require_relative 'lexer/substitution_reader'
require_relative 'lexer/word_scanner'
require_relative 'lexer/token_classifier'

module Rush
  # StringScanner pump that yields [symbol, value] pairs for racc. It skips
  # blanks and comments, then emits NEWLINE, an IO_NUMBER, an operator, or a
  # WORD/ASSIGNMENT_WORD (classified against LexState, which advances after each
  # token to track command position — the seed of POSIX Grammar Rules 1-9).
  class Lexer
    BLANK = /[ \t]+/
    COMMENT = /#[^\n]*/
    IO_NUMBER = /\d+(?=[<>])/

    def initialize(source)
      @scanner = StringScanner.new(source)
      @state = LexState.new
    end

    def location = @scanner.charpos

    def next_token
      skip_insignificant
      return [false, false] if @scanner.eos?

      emit(scan_token)
    end

    private

    def emit(token)
      @state.advance(token.first)
      token
    end

    def skip_insignificant
      loop { break unless @scanner.skip(BLANK) || @scanner.skip(COMMENT) }
    end

    def scan_token
      return [:NEWLINE, "\n"] if @scanner.scan("\n")

      io_number || operator || word
    end

    def io_number
      digits = @scanner.scan(IO_NUMBER)
      digits && [:IO_NUMBER, digits.to_i]
    end

    def operator
      matched = @scanner.scan(OperatorTable::PATTERN)
      matched && [OperatorTable::OPERATORS[matched], matched]
    end

    def word
      TokenClassifier.new(WordScanner.new(@scanner).scan, @state).call
    end
  end
end
