# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Tracks command position (POSIX Grammar Rule 1) plus the for-header and case
    # modes (Rules 4-6): the for NAME and `in`, and the case subject / `in` /
    # pattern / `esac` positions. A compound stack lets nested for/case/if/etc.
    # temporarily use their own header modes inside a case body, then return to
    # the surrounding case body so `;;` and `esac` are classified correctly.
    class LexState
      extend T::Sig

      REDIRECT_OPS = T.let(['<', '>', :DGREAT, :LESSGREAT, :CLOBBER].freeze, T::Array[T.any(String, Symbol)])
      INTRODUCERS = T.let([
        :NEWLINE, ';', '&', '|', '(', ')', :AND_IF, :OR_IF,
        :If, :Then, :Else, :Elif, :Lbrace, :Bang, :While, :Until, :Do, :DSEMI
      ].freeze, T::Array[T.any(String, Symbol)])
      NEUTRAL = T.let(%i[ASSIGNMENT_WORD IO_NUMBER].freeze, T::Array[Symbol])
      OPENERS = T.let({ For: :Done, While: :Done, Until: :Done, If: :Fi,
                        Case: :Esac, Lbrace: :Rbrace, '(': ')' }.freeze,
                      T::Hash[T.any(String, Symbol), T.any(String, Symbol)])
      TRANSITIONS = {
        %i[normal For] => :for_name, %i[case_body For] => :for_name,
        %i[normal Case] => :case_subject, %i[case_body Case] => :case_subject,
        %i[for_name NAME] => :for_in,
        %i[for_in In] => :normal, %i[for_in Do] => :normal,
        %i[for_in NEWLINE] => :normal, [:for_in, ';'] => :normal, [:for_in, '&'] => :normal,
        %i[case_subject WORD] => :case_in, %i[case_in In] => :case_arm,
        %i[case_arm WORD] => :case_pat, %i[case_arm Esac] => :normal,
        [:case_pat, ')'] => :case_body, %i[case_body DSEMI] => :case_arm
      }.freeze

      sig { void }
      def initialize
        @command_position = true
        @expect_filename = false
        @mode = :normal
        @compounds = []
      end

      sig { returns(T::Boolean) }
      def expects_command?
        @command_position && !@expect_filename
      end

      # A command word here is a real command name, so alias substitution applies:
      # the normal mode and a case arm's command list. The for-header and case
      # subject/pattern modes do not expand aliases, even when a newline resets
      # command position.
      sig { returns(T::Boolean) }
      def command_mode?
        @mode == :normal || @mode == :case_body
      end

      sig { returns(T::Boolean) }
      def for_name?
        @mode == :for_name
      end

      sig { returns(T::Boolean) }
      def for_in?
        @mode == :for_in
      end

      sig { returns(T::Boolean) }
      def case_subject?
        @mode == :case_subject
      end

      sig { returns(T::Boolean) }
      def case_in?
        @mode == :case_in
      end

      sig { returns(T::Boolean) }
      def case_arm?
        @mode == :case_arm
      end

      sig { returns(T::Boolean) }
      def case_pat?
        @mode == :case_pat
      end

      sig { params(symbol: T.any(String, Symbol)).void }
      def advance(symbol)
        transition(symbol)
        update_position(symbol)
      end

      private

      sig { params(symbol: T.any(String, Symbol)).void }
      def transition(symbol)
        start_compound(symbol)
        @mode = TRANSITIONS.fetch([@mode, symbol], @mode)
        @mode = T.must(@compounds.pop).last if @compounds.last&.first == symbol
      end

      sig { params(symbol: T.any(String, Symbol)).void }
      def update_position(symbol)
        return @expect_filename = true if REDIRECT_OPS.include?(symbol)
        return reset if INTRODUCERS.include?(symbol)
        return @expect_filename = false if NEUTRAL.include?(symbol)

        consume_word
      end

      sig { params(symbol: T.any(String, Symbol)).void }
      def start_compound(symbol)
        close = OPENERS.fetch(symbol, nil)
        @compounds << [close, @mode] if close && expects_command? && command_mode?
      end

      sig { void }
      def reset
        @command_position = true
        @expect_filename = false
      end

      sig { void }
      def consume_word
        @expect_filename ? (@expect_filename = false) : (@command_position = false)
      end
    end
  end
end
