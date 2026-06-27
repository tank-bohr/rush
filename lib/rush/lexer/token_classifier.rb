# frozen_string_literal: true

module Rush
  class Lexer
    # Classifies a scanned word as WORD or ASSIGNMENT_WORD given the lexer state.
    # A word in the command prefix that matches NAME=... becomes an assignment;
    # everywhere else it is a plain WORD. (Quoted-name handling lands when the
    # word scanner gains quoting.)
    class TokenClassifier
      ASSIGNMENT = /\A([a-zA-Z_]\w*)=(.*)\z/m

      def initialize(word, state)
        @word = word
        @state = state
      end

      def call
        match = assignment_match
        match ? assignment_token(match) : [:WORD, @word]
      end

      private

      def assignment_match
        return nil unless @state.assignment_allowed?

        ASSIGNMENT.match(@word.literal_text)
      end

      def assignment_token(match)
        [:ASSIGNMENT_WORD, AST::Assignment.new(name: match[1], value: AST::Word.literal(match[2]))]
      end
    end
  end
end
