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
        @buffer = SegmentBuffer.new
      end

      sig { returns(AST::Word) }
      def scan
        loop do
          char = @scanner.getch
          return @buffer.word unless char

          step(char)
        end
      end

      private

      sig { params(char: String).void }
      def step(char)
        return dollar if char == '$'
        return backtick if char == '`'
        return escape if char == '\\'

        @buffer << char
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
        @buffer.push(AST::CommandSegment.new(reader.parens, false))
      end

      sig { params(reader: SubstitutionReader).void }
      def arithmetic(reader)
        @scanner.getch
        @buffer.push(AST::ArithSegment.new(reader.arithmetic, false))
      end

      sig { void }
      def backtick
        @buffer.push(AST::CommandSegment.new(SubstitutionReader.new(@scanner).backticks, false))
      end

      sig { void }
      def param
        ref = ParamScanner.new(@scanner).read
        ref ? @buffer.push(AST::ParamSegment.new(ref, false)) : (@buffer << '$')
      end

      sig { void }
      def escape
        char = @scanner.getch
        return if char == "\n" # line continuation, as inside double quotes

        @buffer << ESCAPE_TABLE.escape(char)
      end
    end
  end
end
