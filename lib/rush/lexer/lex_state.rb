# frozen_string_literal: true

module Rush
  class Lexer
    # Tracks command position (POSIX Grammar Rule 1: reserved words, command name
    # and ASSIGNMENT_WORD), whether a redirection operator made the next word a
    # target, and the for-header mode (Rules 5/6: the loop NAME, then `in`).
    class LexState
      REDIRECT_OPS = ['<', '>', :DGREAT, :LESSGREAT, :CLOBBER].freeze
      INTRODUCERS = [
        :NEWLINE, ';', '&', '|', :AND_IF, :OR_IF,
        :If, :Then, :Else, :Elif, :Lbrace, :Bang, :While, :Until, :Do
      ].freeze
      NEUTRAL = %i[ASSIGNMENT_WORD IO_NUMBER].freeze
      MODE_TRANSITIONS = {
        For: :for_name, NAME: :for_in, In: :normal, Do: :normal,
        NEWLINE: :normal, ';' => :normal, '&' => :normal
      }.freeze

      def initialize
        @command_position = true
        @expect_filename = false
        @mode = :normal
      end

      def expects_command? = @command_position && !@expect_filename

      def for_name? = @mode == :for_name

      def for_in? = @mode == :for_in

      def advance(symbol)
        @mode = next_mode(symbol)
        return @expect_filename = true if REDIRECT_OPS.include?(symbol)
        return reset if INTRODUCERS.include?(symbol)
        return @expect_filename = false if NEUTRAL.include?(symbol)

        consume_word
      end

      private

      def next_mode(symbol) = MODE_TRANSITIONS.fetch(symbol, @mode)

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
