# frozen_string_literal: true

module Rush
  module Builtins
    # `command name [arg ...]` runs name as a command, skipping shell functions
    # (so a function can call the builtin it shadows). `command -v name` prints
    # how name resolves — the name itself for a keyword/function/builtin, or the
    # PATH for an external — and exits 127 when it is unknown.
    class Command < Base
      def call
        return verify(operands[1]) if operands.first == '-v'
        return verbose(operands[1]) if operands.first == '-V'

        run(operands)
      end

      private

      def verify(name)
        kind, detail = name && CommandLookup.new(executor).find(name)
        return failure(127) unless kind

        stdout.puts(kind == :file ? detail : name)
        success
      end

      def verbose(name)
        line = name && CommandLookup.new(executor).describe(name)
        stdout.puts(line || "#{name}: not found")
        line ? success : failure(127)
      end

      def run(args)
        return success if args.empty?

        builtin = executor.builtins.fetch(args.first)
        return builtin.new(executor, args, @io).call if builtin

        External.new(executor, args, @io, executor.state.environment.exported).call
      end
    end
  end
end
