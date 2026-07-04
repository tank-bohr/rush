# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `unset [-fv] name ...` — remove each name. The default (and -v) unsets a
    # shell variable; -f unsets a function. Unsetting an absent name succeeds.
    class Unset < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        names.each { |name| remove(name) }
        success
      end

      private

      sig { returns(T::Array[String]) }
      def names
        operands.first&.start_with?('-') ? operands.drop(1) : operands
      end

      sig { returns(T::Boolean) }
      def function?
        operands.first == '-f'
      end

      sig { params(name: String).void }
      def remove(name)
        function? ? state.functions.undefine(name) : state.variables.unset(name)
      end

      sig { returns(ShellState) }
      def state
        executor.state
      end
    end
  end
end
