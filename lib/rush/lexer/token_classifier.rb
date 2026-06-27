# frozen_string_literal: true

module Rush
  class Lexer
    # Classifies a scanned word as WORD or ASSIGNMENT_WORD. A word in the command
    # prefix whose first (unquoted) segment begins with NAME= becomes an
    # assignment; its value is the remainder of the word, preserving the quoted
    # segments (so `x="a b"` assigns "a b"). Everything else is a plain WORD.
    class TokenClassifier
      NAME = /\A([a-zA-Z_]\w*)=/

      def initialize(word, state)
        @word = word
        @state = state
      end

      def call
        name = assignment_name
        name ? assignment_token(name) : [:WORD, @word]
      end

      private

      def assignment_name
        head = @word.segments.first
        return nil unless @state.assignment_allowed? && !head.quoted

        match = NAME.match(head.value)
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
