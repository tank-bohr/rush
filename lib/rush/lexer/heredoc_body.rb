# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Scans an unquoted here-document body into an AST::Word of literal / :param /
    # :command segments. Unlike WordScanner there are no quote delimiters (quotes
    # are literal) and no terminator (it consumes the whole body); a backslash
    # escapes only $, ` and \. Expansion itself is deferred to execution, so the
    # body reflects the variable values at the time the command runs. Parameter
    # references are read by the shared ParamScanner.
    class HeredocBody
      extend T::Sig
      include ScannerPredicates

      ESCAPES = { '$' => '$', '`' => '`', '\\' => '\\' }.freeze
      ESCAPE_TABLE = EscapeTable.new(ESCAPES).freeze

      sig { params(text: String).void }
      def initialize(text)
        @scanner = StringScanner.new(text)
        @segments = T.let([], T::Array[AST::WordSegment[T.untyped]])
        @literal = +''
      end

      sig { returns(AST::Word) }
      def scan
        loop do
          char = @scanner.getch
          return build unless char

          step(char)
        end
      end

      private

      sig { returns(AST::Word) }
      def build
        flush
        AST::Word.new(@segments)
      end

      sig { params(char: String).void }
      def step(char)
        return dollar if char == '$'
        return backtick if char == '`'
        return escape if char == '\\'

        @literal << char
      end

      sig { void }
      def dollar
        peek?('(') ? dollar_paren : param
      end

      sig { void }
      def dollar_paren
        @scanner.getch
        reader = SubstitutionReader.new(@scanner)
        peek?('(') ? arithmetic(reader) : command_sub(reader)
      end

      sig { params(reader: SubstitutionReader).void }
      def command_sub(reader)
        push(AST::CommandSegment.new(reader.parens, false))
      end

      sig { params(reader: SubstitutionReader).void }
      def arithmetic(reader)
        @scanner.getch
        push(AST::ArithSegment.new(reader.arithmetic, false))
      end

      sig { void }
      def backtick
        push(AST::CommandSegment.new(SubstitutionReader.new(@scanner).backticks, false))
      end

      sig { void }
      def param
        ref = ParamScanner.new(@scanner).read
        ref ? push(AST::ParamSegment.new(ref, false)) : (@literal << '$')
      end

      sig { void }
      def escape
        char = @scanner.getch
        return if char == "\n" # line continuation, as inside double quotes

        @literal << ESCAPE_TABLE.escape(char)
      end

      sig { params(segment: AST::WordSegment[T.untyped]).void }
      def push(segment)
        flush
        @segments << segment
      end

      sig { void }
      def flush
        return if @literal.empty?

        @segments << AST::LiteralSegment.new(@literal, false)
        @literal = +''
      end
    end
  end
end
