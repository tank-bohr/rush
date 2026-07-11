# typed: true
# frozen_string_literal: true

module Rush
  class Lexer
    # Scans the interior of a "..." region into the host word's SegmentBuffer:
    # literal runs keep their quoted flag, $ and ` stay live, and a backslash
    # escapes only " \ $ ` — plus the line continuation, whose interactive
    # rules the host owns and injects as a callback. The opening quote is
    # already consumed when this scanner starts; it consumes the closing one.
    class DoubleQuoteScanner
      extend T::Sig
      include ScannerPredicates

      LITERAL = /[^"$\\`]+/
      SPECIAL = ['"', '\\', '$', '`'].freeze

      sig { params(scanner: StringScanner, buffer: SegmentBuffer, continuation: T.proc.void).void }
      def initialize(scanner, buffer, continuation)
        @scanner = scanner
        @buffer = buffer
        @continuation = continuation
      end

      sig { void }
      def scan
        push('') if peek?('"') # "" yields one empty field
        step until done?
        raise IncompleteInput, 'unterminated double quote' if @scanner.eos?

        @scanner.getch
      end

      private

      sig { returns(T::Boolean) }
      def done?
        @scanner.eos? || peek?('"')
      end

      sig { void }
      def step
        return dollar if peek?('$')
        return @buffer.push(DollarScanner.new(@scanner).read_backtick(quoted: true)) if peek?('`')
        return escape if peek?('\\')

        push(@scanner.scan(LITERAL))
      end

      sig { void }
      def escape
        @scanner.getch
        return @continuation.call if peek?("\n")

        SPECIAL.include?(@scanner.peek(1)) ? push(@scanner.getch) : push('\\')
      end

      # A lone `$` that begins no valid reference stays a quoted literal dollar.
      sig { void }
      def dollar
        segment = DollarScanner.new(@scanner).read(quoted: true)
        segment ? @buffer.push(segment) : push('$')
      end

      sig { params(value: T.untyped).void }
      def push(value)
        @buffer.push(AST::LiteralSegment.new(value, true))
      end
    end
  end
end
