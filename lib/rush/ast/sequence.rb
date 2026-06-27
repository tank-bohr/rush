# frozen_string_literal: true

module Rush
  module AST
    # A `;`/newline-separated list of commands and the program root. Runs each
    # in order; the program's status is the last command's (0 when empty).
    class Sequence < Node
      attr_reader :commands

      def initialize(commands)
        super()
        @commands = commands
      end

      def execute(executor)
        commands.reduce(Status.success) { |_, command| executor.run(command) }
      end
    end
  end
end
