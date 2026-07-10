# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `kill [-s sigspec | -sigspec | -signum] pid|%id...` sends a signal (TERM
    # by default) to each process; `kill -0 pid` only checks that it exists.
    # Signal names follow Rush::Signals (case-insensitive, no "SIG" prefix);
    # numbers go straight to the OS so the unnamed ones (16, RT, ...) still
    # work. A %id targets the job's process group (-pid, as dash) — without
    # the terminal half of job control no such group exists, so delivery
    # fails "no such process", status 1, and the job survives (dash parity).
    # `kill -l N` prints the signal name for a number or wait status (128 +
    # signal), and a bare `kill -l` lists the known names. A bad spec or an
    # unresolved %id exits 2; a delivery that fails exits 1.
    class Kill < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        return usage if operands.empty?
        return list(operands.drop(1)) if operands.first == '-l'

        spec, pids = parse
        send_signal(spec, pids)
      end

      private

      # tuple, not Array: parse is destructured into send_signal's two arguments.
      sig { returns([String, T::Array[String]]) }
      # mutant:disable -- for incomplete `-s`, the returned sigspec is ignored:
      # `send_signal` reports usage before resolving any signal when no pid exists.
      def parse
        first = operands.fetch(0)
        return [operands.fetch(1, ''), operands.drop(2)] if first == '-s'
        return [first.delete_prefix('-'), operands.drop(1)] if flag?(first)

        ['TERM', operands]
      end

      sig { params(arg: String).returns(T::Boolean) }
      def flag?(arg)
        arg.start_with?('-') && !arg.eql?('-')
      end

      sig { params(spec: String, pids: T::Array[String]).returns(Status) }
      def send_signal(spec, pids)
        return usage if pids.empty?

        signal = resolve(spec)
        signal ? deliver(signal, pids) : bad("#{spec}: invalid signal specification")
      rescue JobError => e
        bad(e.message)
      end

      # A numeric spec goes straight to the OS (Integer); a name decodes to its
      # canonical String, or nil when the spec is unknown.
      sig { params(spec: String).returns(T.nilable(T.any(Integer, String))) }
      def resolve(spec)
        return Integer(spec) if spec.match?(/\A\d+\z/)

        Signals.decode(spec)
      end

      sig { params(signal: T.any(Integer, String), pids: T::Array[String]).returns(Status) }
      def deliver(signal, pids)
        failed = pids.reject { |pid| send_to(signal, pid) }
        failed.empty? ? success : failure
      end

      # Returns a truthy OS delivery count on success, nil when delivery failed.
      sig { params(signal: T.any(Integer, String), pid: String).returns(T.nilable(Integer)) }
      def send_to(signal, pid)
        target = os_target(pid)
        executor.system.kill(signal, target)
      rescue SystemCallError, ArgumentError, TypeError
        oops("#{pid}: no such process")
      end

      # A %id names the job's process group: negative pid, like dash. An
      # unresolved %id raises JobError past the delivery loop (status 2).
      sig { params(pid: String).returns(Integer) }
      def os_target(pid)
        return -JobSpec.resolve(executor.jobs, pid).pid if pid.start_with?('%')

        Integer(pid)
      end

      sig { params(args: T::Array[String]).returns(Status) }
      def list(args)
        args.empty? ? list_all : list_one(args.fetch(0))
      end

      sig { returns(Status) }
      def list_all
        Signals::NUMBERS.each { |num, name| stdout.puts(name) if num.nonzero? }
        success
      end

      sig { params(arg: String).returns(Status) }
      def list_one(arg)
        name = listed_signal_name(arg)
        name ? ok(name) : invalid_signal(arg)
      end

      sig { params(arg: String).returns(T.nilable(String)) }
      def listed_signal_name(arg)
        return unless arg.match?(/\A\d+\z/)

        num = adjust(Integer(arg))
        return unless num.positive?

        Signals::NUMBERS.fetch(num, nil)
      end

      sig { params(num: Integer).returns(Integer) }
      # mutant:disable -- for `kill -l 128`, `128` and `0` are both invalid;
      # changing the wait-status boundary is observationally equivalent there.
      def adjust(num)
        num >= 129 ? num - 128 : num
      end

      sig { params(name: String).returns(Status) }
      def ok(name)
        stdout.puts(name)
        success
      end

      sig { params(spec: T.nilable(String)).returns(Status) }
      def invalid_signal(spec)
        bad("#{spec}: invalid signal specification")
      end

      sig { returns(Status) }
      def usage
        bad('usage: kill [-s sigspec | -signum] pid ...')
      end

      sig { params(message: String).returns(Status) }
      def bad(message)
        stderr.puts("kill: #{message}")
        failure(2)
      end

      sig { params(message: String).returns(NilClass) }
      def oops(message)
        stderr.puts("kill: #{message}")
      end
    end
  end
end
