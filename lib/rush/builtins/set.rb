# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `set [-/+ options] [--] [arg ...]` — toggle shell options (-x/+x and the
    # `-o name`/`+o name` long form) and, when operands follow (or after `--`),
    # replace the positional parameters. With no operands the parameters are left
    # unchanged; an unknown option is ignored. A bare trailing `-o` writes the
    # current settings table, a bare `+o` the re-input form (POSIX XCU set).
    # Options: -a/allexport, -C/noclobber, -e/errexit, -u/nounset, -x/xtrace,
    # -f/noglob, -v/verbose, pipefail.
    class Set < Base
      extend T::Sig

      OPTIONS = Options::LETTERS
      LONG = Options::LONG

      sig { returns(Status) }
      def call
        rest = strip_options(operands)
        executor.state.positional.replace(rest) if rest
        success
      end

      private

      sig { params(args: T::Array[String]).returns(T.nilable(T::Array[String])) }
      def strip_options(args)
        return if args.empty?

        positionals(args, consume_options(args))
      end

      sig { params(args: T::Array[String]).returns(Integer) }
      def consume_options(args)
        index = 0
        while (cluster = OptionCluster.parse(args[index]))
          index += advance(cluster, args, index)
        end
        index
      end

      sig { params(cluster: OptionCluster, args: T::Array[String], index: Integer).returns(Integer) }
      def advance(cluster, args, index)
        return apply_long(cluster.sign, args[index + 1]) if cluster.letters.join == 'o'

        apply(cluster)
        1
      end

      sig { params(args: T::Array[String], index: Integer).returns(T.nilable(T::Array[String])) }
      def positionals(args, index)
        return if index == args.size

        args[index] == '--' ? args.drop(index + 1) : args.drop(index)
      end

      sig { params(cluster: OptionCluster).void }
      def apply(cluster)
        cluster.each_letter { |char, sign| toggle(OPTIONS.fetch(char, nil), sign) }
      end

      # With a name, toggle that option; bare `set -o` prints the option
      # table (format follows dash), bare `set +o` the lines that re-create
      # the settings when re-input (POSIX XCU set).
      sig { params(sign: T.nilable(String), name: T.nilable(String)).returns(Integer) }
      def apply_long(sign, name)
        return toggle_long(sign, name) if name

        options = executor.state.options
        print_lines(sign == '-' ? ['Current option settings', *options.settings_rows] : options.reinput_lines)
      end

      sig { params(sign: T.nilable(String), name: String).returns(Integer) }
      def toggle_long(sign, name)
        toggle(LONG.fetch(name, nil), sign)
        2
      end

      # Prints a listing and consumes just the bare -o/+o flag itself.
      sig { params(lines: T::Array[String]).returns(Integer) }
      def print_lines(lines)
        lines.each { |line| stdout.puts(line) }
        1
      end

      sig { params(option: T.nilable(Symbol), sign: T.nilable(String)).void }
      def toggle(option, sign)
        return unless option

        enabled = sign == '-'
        # Monitor carries side effects (SIGTSTP disposition, tty check) and can
        # refuse, so it routes through the job-control policy, not bare state.
        return executor.state.set_option(option, enabled) unless option == :monitor

        enabled ? executor.job_control.enable(stderr) : executor.job_control.disable
      end
    end
  end
end
