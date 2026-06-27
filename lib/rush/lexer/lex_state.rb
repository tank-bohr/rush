# frozen_string_literal: true

module Rush
  class Lexer
    # Tracks command position (POSIX Grammar Rule 1) plus the for-header and case
    # modes (Rules 4-6): the for NAME and `in`, and the case subject / `in` /
    # pattern / `esac` positions. Modes are a single token (not a stack), so
    # `for`/`case` nested *directly* inside a case body are not tracked.
    class LexState
      REDIRECT_OPS = ['<', '>', :DGREAT, :LESSGREAT, :CLOBBER].freeze
      INTRODUCERS = [
        :NEWLINE, ';', '&', '|', '(', ')', :AND_IF, :OR_IF,
        :If, :Then, :Else, :Elif, :Lbrace, :Bang, :While, :Until, :Do, :DSEMI
      ].freeze
      NEUTRAL = %i[ASSIGNMENT_WORD IO_NUMBER].freeze
      TRANSITIONS = {
        %i[normal For] => :for_name, %i[normal Case] => :case_subject,
        %i[for_name NAME] => :for_in,
        %i[for_in In] => :normal, %i[for_in Do] => :normal,
        %i[for_in NEWLINE] => :normal, [:for_in, ';'] => :normal, [:for_in, '&'] => :normal,
        %i[case_subject WORD] => :case_in, %i[case_in In] => :case_arm,
        %i[case_arm WORD] => :case_pat, %i[case_arm Esac] => :normal,
        [:case_pat, ')'] => :case_body, %i[case_body DSEMI] => :case_arm
      }.freeze

      def initialize
        @command_position = true
        @expect_filename = false
        @mode = :normal
      end

      def expects_command? = @command_position && !@expect_filename

      # A command word here is a real command name, so alias substitution applies:
      # the normal mode and a case arm's command list. The for-header and case
      # subject/pattern modes do not expand aliases, even when a newline resets
      # command position.
      def command_mode? = @mode == :normal || @mode == :case_body

      def for_name? = @mode == :for_name
      def for_in? = @mode == :for_in
      def case_subject? = @mode == :case_subject
      def case_in? = @mode == :case_in
      def case_arm? = @mode == :case_arm
      def case_pat? = @mode == :case_pat

      def advance(symbol)
        @mode = TRANSITIONS.fetch([@mode, symbol], @mode)
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
