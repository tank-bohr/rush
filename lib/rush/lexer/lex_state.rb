# frozen_string_literal: true

module Rush
  class Lexer
    # Tracks whether the next word is in command position, which drives POSIX
    # Grammar Rule 1 (reserved words and the command name) plus ASSIGNMENT_WORD
    # recognition, and whether a redirection operator has made the next word a
    # target. A reserved word or operator that introduces a command (if/then/do/
    # {/!/|/&&/;/newline/...) returns to command position; the for/case header
    # states (NAME, `in`) are layered on in a later slice.
    class LexState
      REDIRECT_OPS = ['<', '>', :DGREAT, :LESSGREAT, :CLOBBER].freeze
      INTRODUCERS = [
        :NEWLINE, ';', '&', '|', :AND_IF, :OR_IF,
        :If, :Then, :Else, :Elif, :Lbrace, :Bang, :While, :Until, :Do
      ].freeze
      NEUTRAL = %i[ASSIGNMENT_WORD IO_NUMBER].freeze

      def initialize
        @command_position = true
        @expect_filename = false
      end

      def expects_command? = @command_position && !@expect_filename

      def advance(symbol)
        return @expect_filename = true if REDIRECT_OPS.include?(symbol)
        return reset if INTRODUCERS.include?(symbol)
        return @expect_filename = false if NEUTRAL.include?(symbol)

        consume_word
      end

      private

      def reset
        @command_position = true
        @expect_filename = false
      end

      def consume_word
        @expect_filename ? (@expect_filename = false) : (@command_position = false)
      end
    end
  end
end
