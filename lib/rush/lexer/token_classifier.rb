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

      # The assignment-name capture plus the literal segment it came from.
      class AssignmentHead
        extend T::Sig

        sig { returns(String) }
        attr_reader :name, :literal

        sig { params(name: String, literal: String, source_line: Integer).void }
        def initialize(name, literal, source_line)
          @name = name
          @literal = literal
          @source_line = source_line
        end

        sig { params(tail: T::Array[AST::WordSegment[T.untyped]]).returns(AST::Assignment) }
        def assignment(tail)
          AST::Assignment.new(name: name, value: word(tail))
        end

        private

        sig { params(tail: T::Array[AST::WordSegment[T.untyped]]).returns(AST::Word) }
        def word(tail)
          remainder = AST::LiteralSegment.new(literal.delete_prefix("#{name}="), false)
          AST::Word.new([remainder] + tail, source_line: @source_line)
        end
      end

      NAME = /\A([a-zA-Z_]\w*)=/
      # `esac` is a reserved word in command position (POSIX 2.4): it closes a
      # case item whose last list omits `;;`, and is a syntax error elsewhere.
      RESERVED = {
        'if' => :If, 'then' => :Then, 'else' => :Else, 'elif' => :Elif, 'fi' => :Fi,
        'while' => :While, 'until' => :Until, 'do' => :Do, 'done' => :Done,
        'for' => :For, 'case' => :Case, 'esac' => :Esac,
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

        head = assignment_head
        head ? assignment_token(head) : [:WORD, @word]
      end

      sig { returns(T.nilable(Symbol)) }
      def for_header
        lookup(FOR_IN)
      end

      sig { returns(T.nilable(Symbol)) }
      def reserved
        lookup(RESERVED) if @state.expects_command?
      end

      sig { params(table: T::Hash[String, Symbol]).returns(T.nilable(Symbol)) }
      def lookup(table)
        name = @word.literal_name
        name ? table.fetch(name, nil) : nil
      end

      sig { returns(T.nilable(AssignmentHead)) }
      def assignment_head
        return unless @state.expects_command?

        literal = assignment_literal
        return unless literal

        name = capture(literal)
        name ? AssignmentHead.new(name, literal, @word.source_line) : nil
      end

      sig { returns(T.nilable(String)) }
      def assignment_literal
        @word.first_literal_value
      end

      sig { params(value: String).returns(T.nilable(String)) }
      def capture(value)
        match = NAME.match(value)
        match && match[1]
      end

      sig { params(head: AssignmentHead).returns([Symbol, T.untyped]) }
      def assignment_token(head)
        [:ASSIGNMENT_WORD, head.assignment(@word.segments.drop(1))]
      end
    end
  end
end
