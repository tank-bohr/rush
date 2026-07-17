# typed: true
# frozen_string_literal: true

require 'strscan'

module Rush
  module Builtins
    # Renders a printf template against its arguments: literal text (with
    # backslash escapes), %% and the %[flags][width][.prec]conv conversions,
    # cycling the template while arguments remain. Flags/width/precision defer to
    # Ruby's format; numeric conversions coerce their argument (a present
    # non-number is reported via the ok flag and treated as 0, a missing one as
    # 0 silently). %b and octal escapes arrive in a later slice. Returns [text, ok].
    class PrintfFormatter
      extend T::Sig

      NUMERIC = T.let(%w[d i o u x X].freeze, T::Array[String])
      SIGNED = T.let(%w[d i].freeze, T::Array[String])
      INTEGER_PREFIX = T.let(/\A[+-]?(?:0[xX][0-9a-fA-F]+|0[0-7]*|[1-9][0-9]*)/, Regexp)
      SIGNED_MIN = T.let(-(1 << 63), Integer)
      SIGNED_MAX = T.let((1 << 63) - 1, Integer)
      UNSIGNED_MODULUS = T.let(1 << 64, Integer)
      UNSIGNED_MAX = T.let(UNSIGNED_MODULUS - 1, Integer)

      # Scans and walks one pass of a printf template: literal runs and resolved
      # backslash escapes pass straight through, while each %conversion is handed
      # back to the formatter to render against the next argument (double
      # dispatch), so the scanning lives here and the formatting stays there.
      class Template < StringScanner
        extend T::Sig

        ESCAPES = T.let({ '\\' => '\\', 'a' => "\a", 'b' => "\b", 'f' => "\f",
                          'n' => "\n", 'r' => "\r", 't' => "\t", 'v' => "\v" }.freeze,
                        T::Hash[String, String])
        ESCAPE_TABLE = EscapeTable.new(ESCAPES).freeze
        SPEC = /\A([-+ #0]*\d*(?:\.\d+)?)([diouxXcs%])/

        sig { params(formatter: PrintfFormatter).returns(String) }
        def emit(formatter)
          out = +''
          while (char = getch)
            out << piece(formatter, char)
          end
          out
        end

        private

        sig { params(formatter: PrintfFormatter, char: String).returns(String) }
        def piece(formatter, char)
          return conversion(formatter) if char == '%'
          return escape if char == '\\'

          char
        end

        sig { params(formatter: PrintfFormatter).returns(String) }
        def conversion(formatter)
          return '%' unless scan(SPEC)

          flags, conv = T.must(captures)
          formatter.convert(T.must(flags), T.must(conv))
        end

        sig { returns(String) }
        def escape
          ESCAPE_TABLE.escape(getch)
        end
      end

      sig { returns(Integer) }
      attr_reader :errors

      sig { params(args: T::Array[String]).void }
      def initialize(args)
        @args = T.let(args, T::Array[String])
        @cursor = T.let(0, Integer)
        @argument_valid = T.let(true, T::Boolean)
        @errors = T.let(0, Integer)
      end

      sig { params(template: String).returns([String, T::Boolean]) }
      def render(template)
        start = @cursor
        text = Template.new(template).emit(self)
        return [text, @errors.zero?] if @cursor == start || @cursor >= @args.size

        rest, = render(template)
        [text + rest, @errors.zero?]
      end

      # Render one %conversion (called back from Template): %% is a literal %, a
      # numeric/char/string conversion consumes and formats the next argument.
      sig { params(flags: String, conv: String).returns(String) }
      def convert(flags, conv)
        return '%' if conv == '%'

        arg = take
        return numeric(flags, conv, arg) if NUMERIC.include?(conv)
        return format("%#{flags}s", first_char(arg)) if conv == 'c'

        format("%#{flags}s", arg)
      end

      private

      sig { params(flags: String, conv: String, arg: String).returns(String) }
      def numeric(flags, conv, arg)
        @argument_valid = true
        value = to_int(arg)
        value = SIGNED.include?(conv) ? signed_value(value) : unsigned_value(value)
        @errors += 1 unless argument_valid?
        format("%#{flags}#{conv}", value)
      end

      sig { params(arg: String).returns(Integer) }
      def to_int(arg)
        case arg
        when '' then 0
        when /\A['"]/ then quoted_character(arg)
        else parse_integer(arg.lstrip)
        end
      end

      sig { params(arg: String).returns(Integer) }
      def quoted_character(arg)
        character = arg[1]
        character ? character.ord : invalid
      end

      sig { params(source: String).returns(Integer) }
      def parse_integer(source)
        match = INTEGER_PREFIX.match(source)
        return invalid unless match

        value = Integer(T.must(match[0]), 0)
        match.end(0) == source.length ? value : invalid(value)
      end

      sig { params(value: Integer).returns(Integer) }
      def signed_value(value)
        clamp(value, SIGNED_MIN, SIGNED_MAX)
      end

      sig { params(value: Integer).returns(Integer) }
      def unsigned_value(value)
        return clamp(value, 0, UNSIGNED_MAX) if value >= 0

        magnitude = -value
        return invalid(UNSIGNED_MAX) if magnitude > UNSIGNED_MAX

        UNSIGNED_MODULUS - magnitude
      end

      sig { params(value: Integer, minimum: Integer, maximum: Integer).returns(Integer) }
      def clamp(value, minimum, maximum)
        return invalid(minimum) if value < minimum
        return invalid(maximum) if value > maximum

        value
      end

      sig { returns(T::Boolean) }
      def argument_valid?
        @argument_valid
      end

      sig { params(value: Integer).returns(Integer) }
      def invalid(value = 0)
        @argument_valid = false
        value
      end

      sig { returns(String) }
      def take
        arg = @args.fetch(@cursor, '')
        @cursor += 1
        arg
      end

      sig { params(arg: String).returns(T.nilable(String)) }
      def first_char(arg)
        arg.each_char.first
      end
    end
  end
end
