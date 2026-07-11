# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Tracks paren depth and `case` constructs inside a $( ... ) body so
    # ParenReader can tell a pattern-terminating `)` (POSIX case_item — not
    # paren-balanced) from a `)` that counts toward closing the substitution.
    # ParenReader feeds it words and operator events; each open construct is
    # a CaseFrame advancing :case_word → :await_in → :pattern ⇄ :body until
    # `esac` pops it.
    class CaseTracker
      extend T::Sig

      # Keyword words at a command position.
      KEYWORDS = { 'case' => :open_case, 'esac' => :close_case }.freeze
      # Reserved words that keep the next word at a command position.
      CONTINUERS = %w[if then else elif while until do ! {].freeze
      # What a CaseFrame word directive means to the frame stack.
      DIRECTIVES = { pop: :pop_frame, none: :noop }.freeze

      sig { void }
      def initialize
        @frames = T.let([], T::Array[CaseFrame])
        @command = T.let(true, T::Boolean)
        @depth = T.let(1, Integer)
      end

      sig { returns(T::Boolean) }
      def open?
        @depth.positive?
      end

      sig { params(text: String).void }
      def word(text)
        return command_word(text) if state == :body

        send(DIRECTIVES.fetch(T.must(frame).word(text)))
      end

      sig { void }
      def separator
        @command = true
      end

      # dash rejects a newline between a pattern word and its `)` at parse
      # time; abandoning the frame lets the next `)` close the substitution,
      # so the invalid construct fails at the re-parse, as it does in dash.
      sig { void }
      def newline
        separator
        @frames.pop if frame&.marked_pattern?(@depth)
      end

      # After a redirection operator the next word is a target, not a command.
      sig { void }
      def redirect
        @command = false
      end

      sig { void }
      def dsemi
        @command = true
        frame&.reopen(@depth)
      end

      sig { void }
      def open_paren
        @command = true
        frame&.group(@depth)
        @depth += 1
      end

      # True when the just-read `)` stays in the body: either it terminates a
      # case pattern (swallowed, not counted) or it closes a nested paren.
      # False only for the `)` that ends the substitution.
      sig { returns(T::Boolean) }
      def close_paren?
        return true if pattern_close?

        @depth -= 1
        finish_group
        open?
      end

      private

      sig { returns(T.nilable(CaseFrame)) }
      def frame
        @frames.last
      end

      sig { returns(Symbol) }
      def state
        found = frame
        found ? found.state : :body
      end

      sig { returns(T::Boolean) }
      def pattern_close?
        return false unless frame&.pattern?(@depth)

        enter_body
        true
      end

      # A grouped pattern `(x)` closing back to its base depth enters the
      # item's body.
      sig { void }
      def finish_group
        enter_body if frame&.grouped?(@depth)
        @command = true
      end

      sig { void }
      def enter_body
        T.must(frame).body
        @command = true
      end

      sig { params(text: String).void }
      def command_word(text)
        send(KEYWORDS.fetch(text, :noop))
        @command = CONTINUERS.include?(text)
      end

      sig { void }
      def noop; end

      sig { void }
      def pop_frame
        @frames.pop if frame&.at?(@depth)
      end

      sig { void }
      def open_case
        @frames.push(CaseFrame.new(@depth)) if @command
      end

      sig { void }
      def close_case
        pop_frame if @command
      end
    end
  end
end
