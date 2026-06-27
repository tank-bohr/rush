# frozen_string_literal: true

module Rush
  module Builtins
    # `type name ...` — report how each name would be used: a shell keyword,
    # function, special or regular builtin, or the executable found in PATH.
    # Exit status 127 if any name is unknown (the message still goes to stdout).
    class Type < Base
      LABELS = { keyword: 'a shell keyword', function: 'a shell function',
                 special: 'a special shell builtin', builtin: 'a shell builtin' }.freeze

      def call
        unknown = operands.reject { |name| report(name) }
        unknown.empty? ? success : failure(127)
      end

      private

      def report(name)
        found = CommandLookup.new(executor).find(name)
        found ? describe(name, found) : missing(name)
        found
      end

      def describe(name, kind_detail)
        kind, detail = kind_detail
        stdout.puts("#{name} is #{kind == :file ? detail : LABELS.fetch(kind)}")
      end

      def missing(name) = stdout.puts("#{name}: not found")
    end
  end
end
