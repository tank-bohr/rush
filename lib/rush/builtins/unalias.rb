# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `unalias name...` removes each named alias; `unalias -a` removes them all.
    # A name with no alias is reported as `unalias: NAME not found` on stderr with
    # status 1, but the remaining names are still processed.
    class Unalias < Base
      def call
        return remove_all if operands.first == '-a'

        operands.reduce(success) { |status, name| keep(status, remove(name)) }
      end

      private

      def remove_all
        aliases.clear
        success
      end

      def remove(name)
        return success if aliases.remove(name)

        stderr.puts("unalias: #{name} not found")
        failure(1)
      end

      def keep(status, result)
        status.success? ? result : status
      end

      def aliases
        executor.state.aliases
      end
    end
  end
end
