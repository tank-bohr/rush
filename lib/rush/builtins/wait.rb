# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `wait [pid | %id ...]`: with no operands, wait for every known
    # background job (status 0); with operands, wait for each and return the
    # last one's status — 127 when a pid is not a known child, and a %id that
    # resolves to no job is a status-2 error (No such job / No current job,
    # like dash). POSIX gives an unknown last pid its 127 even after a known
    # one; dash instead keeps the last known operand's status — the standard
    # wins (journal). A malformed operand reports on stderr with status 2,
    # and wait is a regular builtin, so the shell carries on (dash-verified).
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

      # Malformed pids are rejected up front (observationally equivalent to
      # dash's lazy check: an already-waited job stays remembered, so a later
      # wait answers the same); %ids validate through resolution itself.
      sig { params(args: T::Array[String]).returns(Status) }
      def each_pid(args)
        malformed = args.find { |operand| !operand.start_with?('%') && !parse(operand) }
        return bad(malformed) if malformed

        args.map { |operand| status_of(operand) }.fetch(-1)
      rescue JobError => e
        no_job(e)
      end

      sig { params(operand: String).returns(Status) }
      def status_of(operand)
        return awaited(job_pid(operand)) if operand.start_with?('%')

        awaited(T.must(parse(operand)))
      end

      sig { params(operand: String).returns(Integer) }
      def job_pid(operand)
        JobSpec.resolve(executor.jobs, operand).pid
      end

      sig { params(error: JobError).returns(Status) }
      def no_job(error)
        stderr.puts("wait: #{error.message}")
        failure(2)
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
