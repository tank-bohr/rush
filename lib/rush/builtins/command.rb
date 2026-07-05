# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `command name [arg ...]` runs name as a command, skipping shell functions
    # (so a function can call the builtin it shadows). `command -v name` prints
    # how name resolves — the name itself for a keyword/function/builtin, or the
    # PATH for an external — and exits 127 when it is unknown.
    class Command < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        return verify(operands[1]) if operands.first == '-v'
        return verbose(operands[1]) if operands.first == '-V'

        run(operands)
      end

      private

      sig { params(name: T.nilable(String)).returns(Status) }
      def verify(name)
        match = CommandLookup.new(executor).find(name)
        return failure(127) unless match.known?

        stdout.puts(match.terse)
        success
      end

      sig { params(name: T.nilable(String)).returns(Status) }
      def verbose(name)
        line = name && CommandLookup.new(executor).describe(name)
        stdout.puts(line || "#{name}: not found")
        line ? success : failure(127)
      end

      sig { params(args: T::Array[String]).returns(Status) }
      def run(args)
        build_command(args).call
      end

      sig { params(args: T::Array[String]).returns(T.any(Base, External)) }
      def build_command(args)
        if args.empty?
          Colon.new(executor, args, io)
        else
          build_named_command(args)
        end
      end

      sig { params(args: T::Array[String]).returns(T.any(Base, External)) }
      def build_named_command(args)
        builtin = executor.builtins.lookup(args.fetch(0))
        build_named_command_from_builtin(args, builtin)
      end

      sig { params(args: T::Array[String], builtin: T.nilable(T.class_of(Base))).returns(T.any(Base, External)) }
      def build_named_command_from_builtin(args, builtin)
        if builtin
          builtin.new(executor, args, io)
        else
          External.new(executor, args, io, exported_env)
        end
      end

      sig { returns(T::Hash[String, String]) }
      def exported_env
        executor.state.variables.exported
      end
    end
  end
end
