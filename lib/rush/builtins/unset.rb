# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `unset [-fv] name ...` — remove each name. The default (and -v) unsets a
    # shell variable; -f unsets a function. Unsetting an absent name succeeds.
    class Unset < Base
      extend T::Sig

      sig { returns(T.untyped) }
      def call
        names.each { |name| remove(name) }
        success
      end

      private

      sig { returns(T.untyped) }
      def names
        operands.first&.start_with?('-') ? operands.drop(1) : operands
      end

      sig { returns(T.untyped) }
      def function?
        operands.first == '-f'
      end

      sig { params(name: T.untyped).returns(T.untyped) }
      def remove(name)
        function? ? state.functions.undefine(name) : state.environment.unset(name)
      end

      sig { returns(T.untyped) }
      def state
        executor.state
      end
    end
  end
end
