# frozen_string_literal: true

require 'etc'
require 'tempfile'

module Rush
  # The sole impure class: every syscall rush makes is a thin wrapper here, so
  # specs inject a fake (spec/support/fake_system_calls.rb) and reach every
  # error branch without touching the real OS. Grows one wrapper per slice.
  class SystemCalls
    # Run argv as an external program. The [cmd, argv0] form forbids the shell
    # path even for a single-word command, so `spawn` never re-interprets words.
    def spawn(env, argv, options) = Process.spawn(env, [argv.first, argv.first], *argv.drop(1), options)

    def waitpid2(pid) = Process.waitpid2(pid)

    # Replace the current process image (the `exec` builtin); the [cmd, argv0]
    # form forbids the shell path, like #spawn. Returns only if the exec fails.
    def exec(env, argv, options) = Process.exec(env, [argv.first, argv.first], *argv.drop(1), options)

    def pid = Process.pid

    # Accumulated CPU times for the `times` builtin: a Process::Tms with utime /
    # stime for the shell and cutime / cstime for its children. Non-deterministic,
    # so the builtin's output is verified by format rather than differentially.
    def times = Process.times

    # Send a signal to a process (the `kill` builtin); signal 0 only probes that
    # the target exists. Real signal delivery cannot run under the test harness.
    # :nocov:
    def kill(signal, pid) = Process.kill(signal, pid)

    # Install a signal disposition for `trap`: a command string ('IGNORE' /
    # 'DEFAULT') or, when nil, the block to run when the signal arrives. Mutating
    # the process's real signal handlers cannot run under the test harness.
    def trap_signal(name, command, &block) = Signal.trap(name, command || block)
    # :nocov:

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

    # Pathname expansion: sorted matches for a glob pattern (backslash escapes
    # are honoured; a leading dot is matched only by an explicit dot). Empty
    # when nothing matches.
    def glob(pattern) = Dir.glob(pattern)

    # Sync so a builtin's write reaches the file immediately — like a pipe write
    # end (sync by default), this lets a forked subshell's output survive its
    # exit! and be visible to a later command; close_redirect releases the fd.
    # rubocop:disable Style/FileOpen -- a redirection keeps the file open past
    # this call, so the auto-closing block form is wrong here.
    def open_file(path, mode) = File.open(path, mode).tap { |io| io.sync = true }
    # rubocop:enable Style/FileOpen

    # Flush and release a file a redirection opened, so a later command in the
    # same shell sees the data and the fd does not leak.
    def close_redirect(io) = io.close

    def read_file(path) = File.read(path)

    # A readable stream carrying a here-document body (a real fd, via a tempfile,
    # so spawned children can read it).
    def here_doc(body)
      Tempfile.new('rush-heredoc').tap do |file|
        file.write(body)
        file.rewind
      end
    end

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

    # Interactive-REPL support: read one line of input (nil at EOF) and report
    # whether standard input is a terminal.
    def read_line = stdin.gets

    def tty? = stdin.tty?

    # Home directory of a named user for ~user tilde expansion, or nil if there
    # is no such user.
    def home_dir(name)
      Etc.getpwnam(name).dir
    rescue ArgumentError
      nil
    end
  end
end
