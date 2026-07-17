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

      sig { params(args: T::Array[String]).void }
      def initialize(args)
        @args = T.let(args, T::Array[String])
        @cursor = T.let(0, Integer)
        @ok = T.let(true, T::Boolean)
      end

      sig { params(template: String).returns([String, T::Boolean]) }
      def render(template)
        start = @cursor
        text = Template.new(template).emit(self)
        return [text, @ok] if @cursor == start || @cursor >= @args.size

        rest, = render(template)
        [text + rest, @ok]
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
        format("%#{flags}#{conv}", to_int(arg))
      end

      sig { params(arg: String).returns(Integer) }
      def to_int(arg)
        return 0 if arg.empty?

        Integer(arg)
      rescue ArgumentError
        invalid
      end

      sig { returns(Integer) }
      def invalid
        @ok = false
        0
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
