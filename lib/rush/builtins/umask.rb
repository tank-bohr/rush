# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `umask [-S] [mode]` — print or set the file creation mask. Octal operands
    # set the mask directly; symbolic operands edit the allowed permission bits
    # (the complement of the mask), as shown by `umask -S`.
    class Umask < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        return illegal_option(operands.first) if invalid_option?

        symbolic, mode = parse_operands
        return change_mask(mode) if mode
        return display_symbolic if symbolic

        display_octal
      end

      private

      sig { returns(Integer) }
      def current_mask
        executor.system.current_umask
      end

      sig { params(mode: String).returns(Status) }
      def change_mask(mode)
        parsed = UmaskMode.parse(mode, current_mask)
        return illegal(mode) unless parsed

        executor.system.change_umask(parsed)
        success
      end

      sig { returns(T::Boolean) }
      def invalid_option?
        operands.any? { |arg| invalid_option_operand?(arg) }
      end

      sig { params(arg: String).returns(T::Boolean) }
      def invalid_option_operand?(arg)
        arg.start_with?('-') && arg != '-S'
      end

      sig { returns([T::Boolean, T.nilable(String)]) }
      def parse_operands
        args = operands.reject { |arg| arg == '-S' }
        [operands.include?('-S'), args.first]
      end

      sig { returns(Status) }
      def display_symbolic
        stdout.puts(UmaskMode.format_symbolic(current_mask))
        success
      end

      sig { returns(Status) }
      def display_octal
        stdout.puts(UmaskMode.format_octal(current_mask))
        success
      end

      sig { params(mode: String).returns(Status) }
      def illegal(mode)
        label = mode.match?(/\A[0-9]+\z/) ? 'number' : 'mode'
        stderr.puts("rush: umask: Illegal #{label}: #{mode}")
        failure(2)
      end

      sig { params(option: T.nilable(String)).returns(Status) }
      def illegal_option(option)
        stderr.puts("rush: umask: Illegal option #{option}")
        failure(2)
      end
    end
  end
end
