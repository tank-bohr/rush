# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # Shared engine of `export` and `readonly`: each operand is `name[=value]` —
    # the value is assigned first when one is given, then the subclass's marking
    # applies on the variable table. Both always report success.
    class Declare < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        operands.each { |operand| declare(operand) }
        success
      end

      private

      # Apply this builtin's marking to one name[=value] operand.
      sig { params(_operand: String).void }
      def declare(_operand)
        raise NotImplementedError
      end
    end
  end
end
