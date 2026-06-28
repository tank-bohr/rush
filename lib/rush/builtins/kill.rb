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
      def call
        return usage if operands.empty?

        operands.first == '-l' ? list(operands.drop(1)) : send_signal(*parse)
      end

      private

      def parse
        return [operands[1], operands.drop(2)] if operands.first == '-s'
        return [operands.first[1..], operands.drop(1)] if flag?(operands.first)

        ['TERM', operands]
      end

      def flag?(arg) = arg.start_with?('-') && arg != '-'

      def send_signal(spec, pids)
        return usage if pids.empty?

        signal = resolve(spec)
        signal ? deliver(signal, pids) : bad("#{spec}: invalid signal specification")
      end

      def resolve(spec)
        return Integer(spec) if spec.match?(/\A\d+\z/)

        Signals.decode(spec)
      end

      def deliver(signal, pids)
        failed = pids.reject { |pid| send_to(signal, pid) }
        failed.empty? ? success : failure(1)
      end

      def send_to(signal, pid)
        executor.system.kill(signal, Integer(pid))
        pid
      rescue SystemCallError, ArgumentError, TypeError
        oops("#{pid}: no such process")
      end

      def list(args) = args.empty? ? list_all : list_one(args.first)

      def list_all
        Signals::NUMBERS.each { |num, name| stdout.puts(name) unless num.zero? }
        success
      end

      def list_one(arg)
        num = arg.match?(/\A\d+\z/) ? adjust(arg.to_i) : 0
        name = num.positive? ? Signals::NUMBERS[num] : nil
        name ? ok(name) : bad("#{arg}: invalid signal specification")
      end

      def adjust(num) = num > 128 ? num - 128 : num

      def ok(name)
        stdout.puts(name)
        success
      end

      def usage = bad('usage: kill [-s sigspec | -signum] pid ...')

      def bad(message)
        stderr.puts("kill: #{message}")
        failure(2)
      end

      def oops(message)
        stderr.puts("kill: #{message}")
        nil
      end
    end
  end
end
