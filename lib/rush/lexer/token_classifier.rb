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
        '{' => :Lbrace, '}' => :Rbrace, '!' => :Bang
      }.freeze

      def initialize(word, state)
        @word = word
        @state = state
      end

      def call
        keyword = reserved
        return [keyword, @word] if keyword

        name = assignment_name
        name ? assignment_token(name) : [:WORD, @word]
      end

      private

      def reserved
        RESERVED[text] if @state.expects_command? && plain?
      end

      def plain? = @word.segments.one? && literal_unquoted?(@word.segments.first)

      def literal_unquoted?(segment) = segment.kind == :literal && !segment.quoted

      def text = @word.segments.first.value

      def assignment_name
        return nil unless @state.expects_command?

        head = @word.segments.first
        literal_unquoted?(head) ? capture(head.value) : nil
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
        remainder = AST::WordSegment.new(kind: :literal, value: head.value[(name.length + 1)..], quoted: false)
        AST::Word.new([remainder] + @word.segments.drop(1))
      end
    end
  end
end
