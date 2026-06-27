# frozen_string_literal: true

module Rush
  module Builtins
    # `echo [-n] [arg...]` — joins arguments with spaces and adds a trailing
    # newline; `-n` suppresses it. XSI escape processing (\n, \t, \c, ...) is
    # added in Phase 2.
    class Echo < Base
      def call
        stdout.write(render)
        success
      end

      private

      def render
        body = printed.join(' ')
        newline? ? "#{body}\n" : body
      end

      def newline? = operands.first != '-n'

      def printed = newline? ? operands : operands.drop(1)
    end
  end
end
