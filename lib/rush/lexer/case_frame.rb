# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # One open `case` construct inside a $( ... ) body: the paren depth it
    # opened at, its position in the grammar — :case_word (subject expected),
    # :await_in (the `in` word expected), :pattern, :body — and whether the
    # current pattern opened with the optional `(` group, whose balanced
    # close also enters the item's body.
    class CaseFrame
      extend T::Sig

      # The per-state handler for a word before the construct's first body.
      FRAME_WORDS = { case_word: :subject_word, await_in: :in_word, pattern: :pattern_word }.freeze
      # Only the word `in` moves a subject to its first pattern.
      AFTER_SUBJECT = { 'in' => :pattern }.freeze
      # `esac` in pattern position asks the tracker to pop the construct.
      POPS = { 'esac' => :pop }.freeze

      sig { returns(Symbol) }
      attr_reader :state

      sig { params(base: Integer).void }
      def initialize(base)
        @base = base
        @state = T.let(:case_word, Symbol)
        @marked = T.let(false, T::Boolean)
        @grouped = T.let(false, T::Boolean)
      end

      sig { params(depth: Integer).returns(T::Boolean) }
      def at?(depth)
        @base == depth
      end

      # The directive (:pop or :none) for a word seen before the body state.
      sig { params(text: String).returns(Symbol) }
      def word(text)
        send(FRAME_WORDS.fetch(@state), text)
      end

      sig { void }
      def body
        @state = :body
      end

      # A `(` before any pattern word opens the grouped `(pattern)` form.
      sig { params(depth: Integer).void }
      def group(depth)
        @grouped = true if pattern_start?(depth)
      end

      sig { params(depth: Integer).returns(T::Boolean) }
      def pattern?(depth)
        @state == :pattern && at?(depth)
      end

      # A pattern that already has words: a newline here is dash's parse error.
      sig { params(depth: Integer).returns(T::Boolean) }
      def marked_pattern?(depth)
        @marked && pattern?(depth)
      end

      sig { params(depth: Integer).returns(T::Boolean) }
      def grouped?(depth)
        @grouped && pattern?(depth)
      end

      # `;;` reopens pattern position for the next case item.
      sig { params(depth: Integer).void }
      def reopen(depth)
        return unless body_at?(depth)

        @state = :pattern
        @marked = false
        @grouped = false
      end

      private

      # The word after `case` is its subject, whatever it spells.
      sig { params(_text: String).returns(Symbol) }
      def subject_word(_text)
        @state = :await_in
        :none
      end

      sig { params(text: String).returns(Symbol) }
      def in_word(text)
        @state = AFTER_SUBJECT.fetch(text, :await_in)
        :none
      end

      # A pattern word was seen: a following `(` is no longer the group form.
      sig { params(text: String).returns(Symbol) }
      def pattern_word(text)
        action = POPS.fetch(text, :none)
        @marked = true unless action == :pop
        action
      end

      sig { params(depth: Integer).returns(T::Boolean) }
      def body_at?(depth)
        @state == :body && at?(depth)
      end

      sig { params(depth: Integer).returns(T::Boolean) }
      def pattern_start?(depth)
        pattern?(depth) && !@marked
      end
    end
  end
end
