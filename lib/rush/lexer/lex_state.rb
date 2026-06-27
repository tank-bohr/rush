# frozen_string_literal: true

module Rush
  class Lexer
    # Tracks position within a command so the classifier can apply POSIX Grammar
    # Rules: ASSIGNMENT_WORD only in the command prefix (before the command name),
    # and a redirection operator makes the next word a target rather than the
    # command name. Reserved-word recognition layers onto this in a later slice.
    class LexState
      COMMAND_DELIMITERS = [:NEWLINE, ';', '&', :AND_IF, :OR_IF, '|'].freeze
      REDIRECT_OPS = ['<', '>', :DGREAT, :LESSGREAT, :CLOBBER].freeze

      def initialize
        @command_position = true
        @expect_filename = false
      end

      def assignment_allowed? = @command_position && !@expect_filename

      def advance(symbol)
        return reset_command if COMMAND_DELIMITERS.include?(symbol)
        return @expect_filename = true if REDIRECT_OPS.include?(symbol)

        consume_word(symbol)
      end

      private

      def reset_command
        @command_position = true
        @expect_filename = false
      end

      def consume_word(symbol)
        return @expect_filename = false if @expect_filename

        @command_position = false if symbol == :WORD
      end
    end
  end
end
