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
      ESCAPES = { '\\' => '\\', 'a' => "\a", 'b' => "\b", 'f' => "\f",
                  'n' => "\n", 'r' => "\r", 't' => "\t", 'v' => "\v" }.freeze
      CONVERSION = /\A%([-+ #0]*\d*(?:\.\d+)?)([diouxXcs%])/
      RUBY_CONV = { 'i' => 'd', 'u' => 'd' }.freeze
      NUMERIC = %w[d i o u x X].freeze

      def initialize(args)
        @args = args
        @cursor = 0
        @ok = true
      end

      def render(template)
        text = one_pass(template)
        return [text, @ok] if last_pass?

        rest, = render(template)
        [text + rest, @ok]
      end

      private

      def last_pass? = @consumed.zero? || @cursor >= @args.size

      def one_pass(template)
        @consumed = 0
        scan = StringScanner.new(template)
        out = +''
        out << chunk(scan) until scan.eos?
        out
      end

      def chunk(scan)
        return conversion(scan) if scan.peek(1) == '%'
        return escape(scan) if scan.peek(1) == '\\'

        scan.scan(/[^%\\]+/)
      end

      def conversion(scan)
        return scan.getch unless scan.scan(CONVERSION)

        apply(scan[1], scan[2])
      end

      def apply(flags, conv)
        return '%' if conv == '%'

        arg = take
        return numeric(flags, conv, arg) if NUMERIC.include?(conv)
        return Kernel.format("%#{flags}s", first_char(arg)) if conv == 'c'

        Kernel.format("%#{flags}s", arg.to_s)
      end

      def numeric(flags, conv, arg) = Kernel.format("%#{flags}#{RUBY_CONV.fetch(conv, conv)}", to_int(arg))

      def to_int(arg)
        return 0 if arg.to_s.empty?

        Integer(arg, exception: false) || invalid
      end

      def invalid
        @ok = false
        0
      end

      def take
        arg = @args[@cursor]
        @cursor += 1
        @consumed += 1
        arg
      end

      def first_char(arg) = arg.to_s[0].to_s

      def escape(scan)
        scan.getch
        char = scan.getch
        ESCAPES.fetch(char) { "\\#{char}" }
      end
    end
  end
end
