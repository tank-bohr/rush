# frozen_string_literal: true

module Rush
  module Builtins
    # `set [--] [arg ...]` — replace the positional parameters with the operands;
    # a leading `--` ends option processing. With no operands they are left
    # unchanged. Option flags (-e, -x) and bare `set`'s variable listing arrive
    # in a later slice.
    class Set < Base
      def call
        executor.state.positional = chosen unless operands.empty?
        success
      end

      private

      def chosen = operands.first == '--' ? operands.drop(1) : operands
    end
  end
end
