# frozen_string_literal: true

module Rush
  module Builtins
    # `type name ...` — report how each name would be used: a shell keyword,
    # function, special or regular builtin, or the executable found in PATH.
    # Exit status 127 if any name is unknown (the message still goes to stdout).
    class Type < Base
      def call
        unknown = operands.reject { |name| report(name) }
        unknown.empty? ? success : failure(127)
      end

      private

      def report(name)
        line = CommandLookup.new(executor).describe(name)
        stdout.puts(line || "#{name}: not found")
        line
      end
    end
  end
end
