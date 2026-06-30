# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `kill [-s sigspec | -sigspec | -signum] pid...` sends a signal (TERM by
    # default) to each process; `kill -0 pid` only checks that it exists. Signal
    # names follow Rush::Signals (case-insensitive, no "SIG" prefix); numbers go
    # straight to the OS so the unnamed ones (16, RT, ...) still work. `kill -l N`
    # prints the signal name for a number or wait status (128 + signal), and a
    # bare `kill -l` lists the known names. A bad spec exits 2; a delivery that
    # fails (no such process) exits 1.
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
      def parse
        first = operands.fetch(0)
        return [operands[1].to_s, operands.drop(2)] if first == '-s'
        return [first[1..].to_s, operands.drop(1)] if flag?(first)

        ['TERM', operands]
      end

      sig { params(arg: String).returns(T::Boolean) }
      def flag?(arg)
        arg.start_with?('-') && arg != '-'
      end

      sig { params(spec: String, pids: T::Array[String]).returns(Status) }
      def send_signal(spec, pids)
        return usage if pids.empty?

        signal = resolve(spec)
        signal ? deliver(signal, pids) : bad("#{spec}: invalid signal specification")
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
        failed.empty? ? success : failure(1)
      end

      # Returns the pid on success (truthy, for #reject), nil when delivery failed.
      sig { params(signal: T.any(Integer, String), pid: String).returns(T.nilable(String)) }
      def send_to(signal, pid)
        executor.system.kill(signal, Integer(pid))
        pid
      rescue SystemCallError, ArgumentError, TypeError
        oops("#{pid}: no such process")
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
        num = arg.match?(/\A\d+\z/) ? adjust(arg.to_i) : 0
        name = num.positive? ? Signals::NUMBERS[num] : nil
        name ? ok(name) : bad("#{arg}: invalid signal specification")
      end

      sig { params(num: Integer).returns(Integer) }
      def adjust(num)
        num > 128 ? num - 128 : num
      end

      sig { params(name: String).returns(Status) }
      def ok(name)
        stdout.puts(name)
        success
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
        nil
      end
    end
  end
end
