# typed: true
# frozen_string_literal: true

module Rush
  # Runs an external program through the system port with the command's env and
  # IoTable, translating the result: the OS exit/signal status, or POSIX 127
  # (not found) / 126 (not executable).
  class External
    def initialize(executor, argv, io, env)
      @executor = executor
      @argv = argv
      @io = io
      @env = env
    end

    def call
      _pid, status = system.waitpid2(system.spawn(@env, @argv, spawn_options))
      Status.of(status)
    rescue Errno::ENOENT, Errno::EACCES => e
      error_status(e)
    end

    private

    def system
      @executor.system
    end

    # close_others closes inherited fds >= 3 (e.g. pipeline pipe ends) in the child.
    def spawn_options
      @io.to_spawn_options.merge(close_others: true)
    end

    def error_status(error)
      code = error.is_a?(Errno::EACCES) ? 126 : 127
      reason = code == 126 ? 'Permission denied' : 'not found'
      @io.get(2).puts("rush: #{@argv.first}: #{reason}")
      Status.new(code)
    end
  end
end
