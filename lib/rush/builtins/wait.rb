# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `wait [pid...]`: with no operands, wait for every known background job
    # (status 0); with pids, wait for each and return the last operand's
    # status — 127 when it is not a known child. POSIX gives an unknown last
    # operand its 127 even after a known one; dash instead keeps the last
    # known operand's status — the standard wins (journal). A malformed
    # operand reports on stderr with status 2, and wait is a regular builtin,
    # so the shell carries on (dash-verified).
    class Wait < Base
      extend T::Sig

      # dash's operand shape: an explicit + sign is accepted; a value past
      # INT_MAX overflows like a non-numeric one; a leading dash reads as an
      # (unsupported) option, except the bare `-`, which is a bad number.
      NUMERIC = /\A\+?\d+\z/

      sig { returns(Status) }
      def call
        args = operands
        args = args.drop(1) if args.first == '--'
        return all if args.empty?

        each_pid(args)
      end

      private

      sig { returns(Status) }
      def all
        executor.jobs.wait_all
        success
      end

      sig { params(args: T::Array[String]).returns(Status) }
      def each_pid(args)
        args.reduce(success) do |_last, operand|
          pid = parse(operand)
          return bad(operand) unless pid

          awaited(pid)
        end
      end

      sig { params(operand: String).returns(T.nilable(Integer)) }
      def parse(operand)
        return unless operand.match?(NUMERIC)

        value = Integer(operand, 10)
        value if value <= INT_MAX
      end

      sig { params(pid: Integer).returns(Status) }
      def awaited(pid)
        executor.jobs.wait_for(pid) || failure(127)
      end

      sig { params(operand: String).returns(Status) }
      def bad(operand)
        stderr.puts("wait: #{diagnosis(operand)}")
        failure(2)
      end

      sig { params(operand: String).returns(String) }
      def diagnosis(operand)
        option?(operand) ? "Illegal option #{operand}" : "Illegal number: #{operand}"
      end

      sig { params(operand: String).returns(T::Boolean) }
      def option?(operand)
        operand.start_with?('-') && operand != '-'
      end
    end
  end
end
