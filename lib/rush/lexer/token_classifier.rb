# frozen_string_literal: true

module Rush
  class Lexer
    # Classifies a scanned word given the lexer state: a reserved word (only an
    # unquoted single-literal word in command position), an ASSIGNMENT_WORD (an
    # unquoted NAME= prefix), or a plain WORD. The assignment value keeps its
    # quoted segments (x="a b").
    class TokenClassifier
      NAME = /\A([a-zA-Z_]\w*)=/
      RESERVED = {
        'if' => :If, 'then' => :Then, 'else' => :Else, 'elif' => :Elif, 'fi' => :Fi,
        'while' => :While, 'until' => :Until, 'do' => :Do, 'done' => :Done,
        'for' => :For, 'case' => :Case,
        '{' => :Lbrace, '}' => :Rbrace, '!' => :Bang
      }.freeze
      FOR_IN = { 'in' => :In, 'do' => :Do }.freeze

      def initialize(word, state)
        @word = word
        @state = state
      end

      def call
        state_token || classify
      end

      private

      def state_token
        forced || header_token
      end

      def forced
        return [:NAME, @word] if @state.for_name?
        return [arm_token, @word] if @state.case_arm?

        [:WORD, @word] if @state.case_subject? || @state.case_pat?
      end

      def header_token
        return [for_header, @word] if @state.for_in? && for_header

        [:In, @word] if @state.case_in? && @word.literal_name == 'in'
      end

      def arm_token = @word.literal_name == 'esac' ? :Esac : :WORD

      def classify
        keyword = reserved
        return [keyword, @word] if keyword

        name = assignment_name
        name ? assignment_token(name) : [:WORD, @word]
      end

      def for_header = FOR_IN[@word.literal_name]

      def reserved
        RESERVED[@word.literal_name] if @state.expects_command?
      end

      def assignment_name
        return nil unless @state.expects_command?

        value = @word.segments.first.literal_value
        capture(value) if value
      end

      def capture(value)
        match = NAME.match(value)
        match && match[1]
      end

      def assignment_token(name)
        [:ASSIGNMENT_WORD, AST::Assignment.new(name: name, value: assignment_value(name))]
      end

      def assignment_value(name)
        head = @word.segments.first
        remainder = AST::LiteralSegment.new(head.value[(name.length + 1)..], false)
        AST::Word.new([remainder] + @word.segments.drop(1))
      end
    end
  end
end
