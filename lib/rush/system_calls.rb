# frozen_string_literal: true

module Rush
  # The sole impure class: every syscall rush makes is a thin wrapper here, so
  # specs inject a fake (spec/support/fake_system_calls.rb) and reach every
  # error branch without touching the real OS. Grows one wrapper per slice.
  class SystemCalls
    # Run argv as an external program. The [cmd, argv0] form forbids the shell
    # path even for a single-word command, so `spawn` never re-interprets words.
    def spawn(env, argv, options) = Process.spawn(env, [argv.first, argv.first], *argv.drop(1), options)

    def waitpid2(pid) = Process.waitpid2(pid)

    def pid = Process.pid

    def pipe = IO.pipe

    # fork/exit! replace or split the process and so cannot run in-process under
    # the test harness; the child-side logic they drive is extracted into pure
    # methods that ARE tested, and real behaviour is covered by subprocess specs.
    # exit! flushes the standard streams first: $stdout is unbuffered only when a
    # tty, so a forked child running a builtin would otherwise lose its output.
    # :nocov:
    def fork(&) = Process.fork(&)

    def exit!(code)
      stdout.flush
      stderr.flush
      Process.exit!(code)
    end
    # :nocov:

    def chdir(path) = Dir.chdir(path)

    def pwd = Dir.pwd

    def expand_path(path, base) = File.expand_path(path, base)

    def fnmatch(pattern, str) = File.fnmatch(pattern, str, File::FNM_DOTMATCH)

    def open_file(path, mode) = File.open(path, mode)

    def read_file(path) = File.read(path)

    # File-test queries for the test/[ builtin (-e -f -d -r -w -x -s -h/-L).
    def exist?(path) = File.exist?(path)

    def file?(path) = File.file?(path)

    def directory?(path) = File.directory?(path)

    def readable?(path) = File.readable?(path)

    def writable?(path) = File.writable?(path)

    def executable?(path) = File.executable?(path)

    def file_nonempty?(path) = File.size?(path).to_i.positive?

    def symlink?(path) = File.symlink?(path)

    def stdin = $stdin

    def stdout = $stdout

    def stderr = $stderr
  end
end
