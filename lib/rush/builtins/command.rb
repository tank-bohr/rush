# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `command [-p] name [arg ...]` runs name as a command, skipping shell
    # functions (so a function can call the builtin it shadows); -p searches
    # the system default PATH (confstr _CS_PATH) for an external instead of
    # $PATH, without changing the child's environment. `command -v name`
    # prints how name resolves — the name itself for a keyword / function /
    # builtin, the path for an external — and -V the long `type` form; both
    # exit 127 for an unknown name, 0 with no operand, and -V outranks -v.
    class Command < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        opts = CommandOptions.new(operands)
        bad = opts.illegal
        bad ? illegal_option(bad) : dispatch(opts)
      end

      private

      sig { params(opts: CommandOptions).returns(Status) }
      def dispatch(opts)
        return no_name(opts) unless opts.name
        return verbose(opts) if opts.verbose?
        return verify(opts) if opts.verify?

        run(opts)
      end

      # dash exits 0 for a bare `command`, `command -v` and `command -V` alike
      # (probed); the bare run form is the colon builtin's no-op.
      sig { params(opts: CommandOptions).returns(Status) }
      def no_name(opts)
        return success if opts.verbose? || opts.verify?

        Colon.new(executor, [], io).call
      end

      sig { params(opts: CommandOptions).returns(Status) }
      def verify(opts)
        print_terse(lookup(opts).find(opts.name))
      end

      sig { params(match: CommandLookup::Match).returns(Status) }
      def print_terse(match)
        return failure(127) unless match.known?

        stdout.puts(match.terse)
        success
      end

      sig { params(opts: CommandOptions).returns(Status) }
      def verbose(opts)
        print_description(T.must(opts.name), lookup(opts).find(opts.name))
      end

      sig { params(name: String, match: CommandLookup::Match).returns(Status) }
      def print_description(name, match)
        return not_described(name) unless match.known?

        stdout.puts(match.describe)
        success
      end

      sig { params(name: String).returns(Status) }
      def not_described(name)
        stdout.puts("#{name}: not found")
        failure(127)
      end

      sig { params(opts: CommandOptions).returns(CommandLookup) }
      def lookup(opts)
        opts.default_path? ? default_lookup : CommandLookup.new(executor)
      end

      sig { returns(CommandLookup) }
      def default_lookup
        CommandLookup.new(executor, path: executor.system.default_path)
      end

      sig { params(opts: CommandOptions).returns(Status) }
      def run(opts)
        name = T.must(opts.name)
        builtin = executor.builtins.lookup(name)
        builtin ? run_builtin(builtin, opts) : run_external(name, opts)
      end

      sig { params(builtin: T.class_of(Base), opts: CommandOptions).returns(Status) }
      def run_builtin(builtin, opts)
        builtin.new(executor, opts.operands, io, command_environment).call
      rescue ParseError, ExpansionError, ReadonlyError, BuiltinError => e
        demoted_error(e)
      end

      sig { params(error: StandardError).returns(Status) }
      def demoted_error(error)
        stderr.puts("rush: #{error.message}")
        failure(2)
      end

      sig { params(name: String, opts: CommandOptions).returns(Status) }
      def run_external(name, opts)
        external = External.new(executor, opts.operands, io, command_environment)
        return external.call unless opts.default_path?

        run_on_default_path(name, external)
      end

      # The default-PATH resolution happens here in the shell (dash does the
      # same): the resolved file is executed while argv[0] stays the name as
      # typed, and $PATH is neither consulted nor mutated.
      sig { params(name: String, external: External).returns(Status) }
      def run_on_default_path(name, external)
        path = default_lookup.executable_path(name)
        path ? external.call_file(path) : not_found(name)
      end

      sig { params(name: String).returns(Status) }
      def not_found(name)
        stderr.puts("rush: #{name}: not found")
        failure(127)
      end

      sig { params(letter: String).returns(Status) }
      def illegal_option(letter)
        stderr.puts("rush: command: Illegal option #{letter}")
        failure(2)
      end
    end
  end
end
