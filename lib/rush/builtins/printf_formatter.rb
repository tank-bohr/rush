# typed: false
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
      RUBY_CONV = { 'i' => 'd', 'u' => 'd' }.freeze
      NUMERIC = %w[d i o u x X].freeze

      # Scans and walks one pass of a printf template: literal runs and resolved
      # backslash escapes pass straight through, while each %conversion is handed
      # back to the formatter to render against the next argument (double
      # dispatch), so the scanning lives here and the formatting stays there.
      class Template < StringScanner
        ESCAPES = { '\\' => '\\', 'a' => "\a", 'b' => "\b", 'f' => "\f",
                    'n' => "\n", 'r' => "\r", 't' => "\t", 'v' => "\v" }.freeze
        ESCAPE_TABLE = EscapeTable.new(ESCAPES).freeze
        SPEC = /\A([-+ #0]*\d*(?:\.\d+)?)([diouxXcs%])/

        def emit(formatter)
          out = +''
          while (char = getch)
            out << piece(formatter, char)
          end
          out
        end

        private

        def piece(formatter, char)
          return conversion(formatter) if char == '%'
          return escape if char == '\\'

          char
        end

        def conversion(formatter)
          return '%' unless scan(SPEC)

          flags, conv = captures
          formatter.convert(flags, conv)
        end

        def escape
          ESCAPE_TABLE.escape(getch)
        end
      end

      def initialize(args)
        @args = args
        @cursor = 0
        @consumed = 0
        @ok = true
      end

      def render(template)
        text = one_pass(template)
        return [text, @ok] if last_pass?

        rest, = render(template)
        [text + rest, @ok]
      end

      # Render one %conversion (called back from Template): %% is a literal %, a
      # numeric/char/string conversion consumes and formats the next argument.
      def convert(flags, conv)
        return '%' if conv == '%'

        arg = take
        return numeric(flags, conv, arg) if NUMERIC.include?(conv)
        return Kernel.format("%#{flags}s", first_char(arg)) if conv == 'c'

        Kernel.format("%#{flags}s", arg)
      end

      private

      def last_pass?
        @consumed.zero? || @cursor >= @args.size
      end

      def one_pass(template)
        @consumed = 0
        Template.new(template).emit(self)
      end

      def numeric(flags, conv, arg)
        Kernel.format("%#{flags}#{RUBY_CONV.fetch(conv, conv)}", to_int(arg))
      end

      def to_int(arg)
        return 0 if arg.empty?

        Integer(arg, exception: false) || invalid
      end

      def invalid
        @ok = false
        0
      end

      def take
        arg = @args.fetch(@cursor, '')
        @cursor += 1
        @consumed += 1
        arg
      end

      def first_char(arg)
        arg.each_char.first || ''
      end
    end
  end
end
