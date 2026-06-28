# frozen_string_literal: true

module Rush
  module Builtins
    # `set [-/+ options] [--] [arg ...]` — toggle shell options (-x/+x and the
    # `-o name`/`+o name` long form) and, when operands follow (or after `--`),
    # replace the positional parameters. With no operands the parameters are left
    # unchanged; an unknown option is ignored. Options: -e/errexit, -u/nounset,
    # -x/xtrace, -f/noglob, -v/verbose.
    class Set < Base
      OPTIONS = { 'e' => :errexit, 'u' => :nounset, 'x' => :xtrace, 'f' => :noglob, 'v' => :verbose }.freeze
      LONG = { 'errexit' => :errexit, 'nounset' => :nounset, 'xtrace' => :xtrace,
               'noglob' => :noglob, 'verbose' => :verbose }.freeze

      def call
        rest = strip_options(operands)
        executor.state.positional = rest if rest
        success
      end

      private

      def strip_options(args)
        return nil if args.empty?

        positionals(args, consume_options(args))
      end

      def consume_options(args)
        index = 0
        index += advance(args, index) while index < args.size && option?(args[index])
        index
      end

      def advance(args, index)
        arg = args[index]
        return apply_long(arg[0], args[index + 1]) if arg[1..] == 'o'

        apply(arg)
        1
      end

      def positionals(args, index)
        return nil if index == args.size

        args[index] == '--' ? args[(index + 1)..] : args[index..]
      end

      def option?(flag) = flag.is_a?(String) && flag.length > 1 && flag != '--' && '-+'.include?(flag[0])

      def apply(flag)
        sign, *letters = flag.chars
        letters.each { |char| toggle(OPTIONS[char], sign) }
      end

      def apply_long(sign, name)
        toggle(LONG[name], sign)
        2
      end

      def toggle(option, sign)
        option && executor.state.set_option(option, sign == '-')
      end
    end
  end
end
