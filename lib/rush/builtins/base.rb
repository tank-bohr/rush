# frozen_string_literal: true

module Rush
  module Builtins
    # Base for builtins. Subclasses implement #call returning a Status. Shared
    # helpers keep each builtin tiny.
    class Base
      def initialize(executor, argv)
        @executor = executor
        @argv = argv
      end

      def call = raise NotImplementedError

      private

      attr_reader :executor, :argv

      def operands = argv.drop(1)

      def stdout = executor.system.stdout

      def success = Status.success

      def failure(code = 1) = Status.failure(code)
    end
  end
end
