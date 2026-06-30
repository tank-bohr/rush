# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Classifies a scanned word given the lexer state: a reserved word (only an
    # unquoted single-literal word in command position), an ASSIGNMENT_WORD (an
    # unquoted NAME= prefix), or a plain WORD. The assignment value keeps its
    # quoted segments (x="a b").
    class TokenClassifier
      extend T::Sig

      NAME = /\A([a-zA-Z_]\w*)=/
      RESERVED = {
        'if' => :If, 'then' => :Then, 'else' => :Else, 'elif' => :Elif, 'fi' => :Fi,
        'while' => :While, 'until' => :Until, 'do' => :Do, 'done' => :Done,
        'for' => :For, 'case' => :Case,
        '{' => :Lbrace, '}' => :Rbrace, '!' => :Bang
      }.freeze
      FOR_IN = { 'in' => :In, 'do' => :Do }.freeze

      sig { params(word: AST::Word, state: LexState).void }
      def initialize(word, state)
        @word = word
        @state = state
      end

      sig { returns([Symbol, T.untyped]) }
      def call
        state_token || classify
      end

      private

      sig { returns(T.nilable([Symbol, T.untyped])) }
      def state_token
        forced || header_token
      end

      sig { returns(T.nilable([Symbol, T.untyped])) }
      def forced
        return [:NAME, @word] if @state.for_name?
        return [arm_token, @word] if @state.case_arm?

        [:WORD, @word] if @state.case_subject? || @state.case_pat?
      end

      sig { returns(T.nilable([Symbol, T.untyped])) }
      def header_token
        keyword = for_header
        return [keyword, @word] if @state.for_in? && keyword

        [:In, @word] if @state.case_in? && @word.literal_name == 'in'
      end

      sig { returns(Symbol) }
      def arm_token
        @word.literal_name == 'esac' ? :Esac : :WORD
      end

      sig { returns([Symbol, T.untyped]) }
      def classify
        keyword = reserved
        return [keyword, @word] if keyword

        name = assignment_name
        name ? assignment_token(name) : [:WORD, @word]
      end

      sig { returns(T.nilable(Symbol)) }
      def for_header
        FOR_IN[@word.literal_name.to_s]
      end

      sig { returns(T.nilable(Symbol)) }
      def reserved
        RESERVED[@word.literal_name.to_s] if @state.expects_command?
      end

      sig { returns(T.nilable(String)) }
      def assignment_name
        return unless @state.expects_command?

        value = @word.segments.first.literal_value
        capture(value) if value
      end

      sig { params(value: T.untyped).returns(T.nilable(String)) }
      def capture(value)
        match = NAME.match(value)
        match && match[1]
      end

      sig { params(name: String).returns([Symbol, T.untyped]) }
      def assignment_token(name)
        [:ASSIGNMENT_WORD, AST::Assignment.new(name: name, value: assignment_value(name))]
      end

      sig { params(name: String).returns(T.untyped) }
      def assignment_value(name)
        head = @word.segments.first
        remainder = AST::LiteralSegment.new(head.value[(name.length + 1)..], false)
        AST::Word.new([remainder] + @word.segments.drop(1))
      end
    end
  end
end
