# typed: true
# frozen_string_literal: true

require 'strscan'

module Rush
  class Lexer
    # Scans the operator word of a ${...} that appeared in a quoted context
    # (double quotes or a here-doc body) into an AST::Word, following dash:
    # $ and ` stay live, a backslash escapes " \ $ ` and the } it protected
    # from closing the reference, embedded double quotes are removed (their
    # content was already quoted), and single quotes are ordinary characters.
    class QuotedWord
      extend T::Sig
      include ScannerPredicates

      ESCAPES = { '"' => '"', '\\' => '\\', '$' => '$', '`' => '`', '}' => '}' }.freeze
      ESCAPE_TABLE = EscapeTable.new(ESCAPES).freeze
      DISPATCH = { '$' => :dollar, '`' => :backtick, '\\' => :escape }.freeze

      sig { params(text: String).void }
      def initialize(text)
        @scanner = StringScanner.new(text)
        @buffer = SegmentBuffer.new
      end

      sig { returns(AST::Word) }
      def word
        step until @scanner.eos?
        @buffer.word
      end

      private

      sig { void }
      def step
        char = T.must(@scanner.getch)
        return if char == '"'

        handler = DISPATCH.fetch(char, nil)
        handler ? send(handler) : (@buffer << char)
      end

      # A lone `$` that begins no valid reference stays a literal dollar.
      sig { void }
      def dollar
        @scanner.unscan
        segment = DollarScanner.new(@scanner).read(quoted: true)
        segment ? @buffer.push(segment) : (@buffer << '$')
      end

      sig { void }
      def backtick
        @scanner.unscan
        @buffer.push(DollarScanner.new(@scanner).read_backtick(quoted: true))
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
