# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `jobs [-l|-p] [%id...]`: list background jobs, newest first, + and -
    # marking the current and previous job, states Running / Done / Done(n) /
    # a signal description. -l inserts the pid after the mark; -p prints only
    # pids. The command column (34) stays empty away from a tty, exactly like
    # dash, which keeps no command text there. Displaying a finished job
    # frees its entry (-p does not); a bad %id reports No such job with
    # status 2 after the entries already rendered (dash-verified).
    class Jobs < Base
      extend T::Sig

      # The flag picks a rendering style; anything else is an illegal option.
      STYLES = T.let({ nil => :short_line, '-l' => :long_line, '-p' => :pid_line }.freeze,
                     T::Hash[T.nilable(String), Symbol])

      sig { returns(Status) }
      def call
        executor.jobs.poll
        flag, args = split_flag(operands)
        STYLES.key?(flag) ? show(STYLES.fetch(flag), args) : bad("Illegal option #{flag}")
      rescue JobError => e
        bad(e.message)
      end

      private

      # tuple: the optional leading -flag and the remaining %id operands.
      sig { params(args: T::Array[String]).returns([T.nilable(String), T::Array[String]]) }
      def split_flag(args)
        args.first&.start_with?('-') ? [args.fetch(0), args.drop(1)] : [nil, args]
      end

      sig { params(style: Symbol, args: T::Array[String]).returns(Status) }
      def show(style, args)
        each_selected(args) { |job| T.unsafe(self).send(style, job) }
        success
      end

      # Resolution stays interleaved with rendering so a bad %id aborts after
      # the entries before it have already been printed, as dash does.
      sig { params(args: T::Array[String], blk: T.proc.params(job: JobTable::Job).returns(T.untyped)).void }
      def each_selected(args, &blk)
        return executor.jobs.ordered.each(&blk) if args.empty?

        args.each { |spec| yield(JobSpec.resolve(executor.jobs, spec)) }
      end

      sig { params(job: JobTable::Job).void }
      def pid_line(job)
        stdout.puts(job.pid)
      end

      sig { params(job: JobTable::Job).void }
      def long_line(job)
        report(job, "#{job.pid} ")
      end

      sig { params(job: JobTable::Job).void }
      def short_line(job)
        report(job, '')
      end

      # dash's column layout: "[n] mark " (plus "pid " under -l), the state,
      # then padding so the (empty, off-tty) command text starts at column 34.
      # A displayed finished job is freed; the bare-pid style never frees.
      sig { params(job: JobTable::Job, pid_field: String).void }
      def report(job, pid_field)
        stdout.puts("[#{job.number}] #{mark(job)} #{pid_field}#{state(job)}".ljust(33))
        executor.jobs.forget(job) unless job.running?
      end

      sig { params(job: JobTable::Job).returns(String) }
      def mark(job)
        index = T.must(executor.jobs.ordered.index(job))
        ['+', '-'].fetch(index, ' ')
      end

      sig { params(job: JobTable::Job).returns(String) }
      def state(job)
        raw = job.raw
        raw ? finished_state(raw) : 'Running'
      end

      sig { params(raw: Process::Status).returns(String) }
      def finished_state(raw)
        signal = raw.termsig
        return Signals.description(signal) if signal

        code = T.must(raw.exitstatus)
        code.zero? ? 'Done' : "Done(#{code})"
      end

      sig { params(message: String).returns(Status) }
      def bad(message)
        stderr.puts("jobs: #{message}")
        failure(2)
      end
    end
  end
end
