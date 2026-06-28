# frozen_string_literal: true

module Rush
  module Builtins
    # `unset [-fv] name ...` — remove each name. The default (and -v) unsets a
    # shell variable; -f unsets a function. Unsetting an absent name succeeds.
    class Unset < Base
      def call
        names.each { |name| remove(name) }
        success
      end

      private

      def names
        operands.first&.start_with?('-') ? operands.drop(1) : operands
      end

      def function?
        operands.first == '-f'
      end

      def remove(name)
        function? ? state.functions.undefine(name) : state.environment.unset(name)
      end

      def state
        executor.state
      end
    end
  end
end
