# frozen_string_literal: true

module Rush
  # Runs an external program through the system port and translates the result:
  # the OS exit/signal status, or POSIX 127 (not found) / 126 (not executable).
  class External
    def initialize(executor, argv)
      @executor = executor
      @argv = argv
    end

    def call
      _pid, status = system.waitpid2(system.spawn(env, @argv, {}))
      Status.of(status)
    rescue Errno::ENOENT, Errno::EACCES => e
      error_status(e)
    end

    private

    def system = @executor.system

    def env = @executor.state.environment.exported

    def error_status(error)
      code = error.is_a?(Errno::EACCES) ? 126 : 127
      reason = code == 126 ? 'Permission denied' : 'not found'
      system.stderr.puts("rush: #{@argv.first}: #{reason}")
      Status.new(code)
    end
  end
end
