# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `set [-/+ options] [--] [arg ...]` — toggle shell options (-x/+x and the
    # `-o name`/`+o name` long form) and, when operands follow (or after `--`),
    # replace the positional parameters. With no operands the parameters are left
    # unchanged; an unknown option is ignored. Options: -a/allexport, -C/noclobber,
    # -e/errexit, -u/nounset, -x/xtrace, -f/noglob, -v/verbose, pipefail.
    class Set < Base
      extend T::Sig

      OPTIONS = { 'a' => :allexport, 'C' => :noclobber, 'e' => :errexit, 'u' => :nounset,
                  'x' => :xtrace, 'f' => :noglob, 'v' => :verbose }.freeze
      LONG = { 'allexport' => :allexport, 'noclobber' => :noclobber,
               'errexit' => :errexit, 'nounset' => :nounset,
               'xtrace' => :xtrace, 'noglob' => :noglob, 'verbose' => :verbose,
               'pipefail' => :pipefail }.freeze

      sig { returns(Status) }
      def call
        rest = strip_options(operands)
        executor.state.positional.replace(rest) if rest
        success
      end

      private

      sig { params(args: T::Array[String]).returns(T.nilable(T::Array[String])) }
      def strip_options(args)
        return if args.empty?

        positionals(args, consume_options(args))
      end

      sig { params(args: T::Array[String]).returns(Integer) }
      def consume_options(args)
        index = 0
        index += advance(args, index) while index < args.size && option?(args[index])
        index
      end

      sig { params(args: T::Array[String], index: Integer).returns(Integer) }
      def advance(args, index)
        arg = args.fetch(index)
        sign, *letters = arg.chars
        return apply_long(sign, args[index + 1]) if letters.join == 'o'

        apply(arg)
        1
      end

      sig { params(args: T::Array[String], index: Integer).returns(T.nilable(T::Array[String])) }
      def positionals(args, index)
        return if index == args.size

        args[index] == '--' ? args.drop(index + 1) : args.drop(index)
      end

      sig { params(flag: T.nilable(String)).returns(T::Boolean) }
      def option?(flag)
        flag.is_a?(String) && flag.length > 1 && flag != '--' && flag.start_with?('-', '+')
      end

      sig { params(flag: String).void }
      def apply(flag)
        sign, *letters = flag.chars
        letters.each { |char| toggle(OPTIONS.fetch(char, nil), sign) }
      end

      sig { params(sign: T.nilable(String), name: T.nilable(String)).returns(Integer) }
      def apply_long(sign, name)
        toggle(name && LONG.fetch(name, nil), sign)
        2
      end

      sig { params(option: T.nilable(Symbol), sign: T.nilable(String)).void }
      def toggle(option, sign)
        return unless option

        enabled = sign == '-'
        executor.state.options.set(option, enabled)
        executor.state.variables.allexport = enabled if option == :allexport
      end
    end
  end
end
