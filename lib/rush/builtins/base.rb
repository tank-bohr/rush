# frozen_string_literal: true

module Rush
  module Builtins
    # Base for builtins. Subclasses implement #call returning a Status. Streams
    # come from the per-command IoTable so redirections apply to builtins too.
    class Base
      def initialize(executor, argv, io)
        @executor = executor
        @argv = argv
        @io = io
      end

      def call = raise NotImplementedError

      private

      attr_reader :executor, :argv

      def operands = argv.drop(1)

      def stdout = @io.get(1)

      def stderr = @io.get(2)

      def success = Status.success

      def failure(code = 1) = Status.failure(code)
    end
  end
end
