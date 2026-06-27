# frozen_string_literal: true

module Rush
  module Builtins
    # `export name[=value] ...` — mark each name for inclusion in the environment
    # of subsequently executed commands, assigning the value first when one is
    # given. (The `-p` listing form arrives with the variable-printing slice.)
    class Export < Base
      def call
        operands.each { |operand| declare(operand) }
        success
      end

      private

      def declare(operand)
        name, value = operand.split('=', 2)
        environment.assign(name, value) if value
        environment.export(name)
      end

      def environment = executor.state.environment
    end
  end
end
