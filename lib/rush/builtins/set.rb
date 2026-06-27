# frozen_string_literal: true

module Rush
  module Builtins
    # `set [-/+ options] [--] [arg ...]` — toggle shell options (-x/+x and the
    # `-o name`/`+o name` long form) and, when operands follow (or after `--`),
    # replace the positional parameters. With no operands the parameters are left
    # unchanged; an unknown option is ignored. Options: -e/errexit, -u/nounset,
    # -x/xtrace.
    class Set < Base
      OPTIONS = { 'e' => :errexit, 'u' => :nounset, 'x' => :xtrace }.freeze
      LONG = { 'errexit' => :errexit, 'nounset' => :nounset, 'xtrace' => :xtrace }.freeze

      def call
        rest = strip_options(operands)
        executor.state.positional = rest unless rest.nil?
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
        return apply_long(args[index][0], args[index + 1]) if args[index][1..] == 'o'

        apply(args[index])
        1
      end

      def positionals(args, index)
        return nil if index == args.size

        args[index] == '--' ? args[(index + 1)..] : args[index..]
      end

      def option?(flag) = flag.is_a?(String) && flag.length > 1 && flag != '--' && '-+'.include?(flag[0])

      def apply(flag)
        flag[1..].each_char { |char| toggle(OPTIONS[char], flag[0]) }
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
