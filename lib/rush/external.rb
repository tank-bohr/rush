# typed: true
# frozen_string_literal: true

module Rush
  # Runs an external program through the system port with the command's env and
  # IoTable, translating the result: the OS exit/signal status, or POSIX 127
  # (not found) / 126 (not executable).
  class External
    extend T::Sig

    sig { params(executor: Executor, argv: T::Array[String], io: IoTable, env: T::Hash[String, String]).void }
    def initialize(executor, argv, io, env)
      @executor = executor
      @argv = argv
      @io = io
      @env = env
    end

    # Under job control the spawned command has no child-side hook, so the
    # foreground wrapper's parent-side give is what hands it the terminal —
    # right after the spawn, before the wait.
    sig { returns(Status) }
    def call
      pid = system.spawn(@env, @argv, spawn_options)
      @executor.job_control.foreground([pid]) { @executor.jobs.await(pid) }
    rescue Errno::ENOENT, Errno::EACCES => e
      error_status(e)
    end

    private

    sig { returns(SystemCalls) }
    def system
      @executor.system
    end

    # close_others closes inherited fds >= 3 (e.g. pipeline pipe ends) in the
    # child. Under job control the command is a job of its own: pgroup: true
    # has the kernel start it as its own process-group leader — the spawn-path
    # equivalent of the fork paths' double setpgid, with no race at all.
    sig { returns(T::Hash[T.any(Integer, Symbol), T.untyped]) }
    def spawn_options
      base = @io.to_spawn_options.merge(close_others: true)
      @executor.job_control.monitored? ? base.merge(pgroup: true) : base
    end

    sig { params(error: SystemCallError).returns(Status) }
    def error_status(error)
      code = error.is_a?(Errno::EACCES) ? 126 : 127
      reason = code == 126 ? 'Permission denied' : 'not found'
      report_error(reason)
      Status.new(code)
    end

    sig { params(reason: String).void }
    def report_error(reason)
      @io.get(2).puts("rush: #{@argv.first}: #{reason}")
    rescue Errno::EBADF
      nil
    end
  end
end
