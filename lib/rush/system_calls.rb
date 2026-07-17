# typed: true
# frozen_string_literal: true

require 'etc'
require 'reline'
require 'tempfile'
require_relative 'system_calls/file_tests'
require_relative 'system_calls/collation'
require_relative 'system_calls/process_identity'
require_relative 'system_calls/process_control'
require_relative 'system_calls/resource_limits'

module Rush
  # The sole impure class: every syscall rush makes is a thin wrapper here, so
  # specs inject a fake (spec/support/fake_system_calls.rb) and reach every
  # error branch without touching the real OS. Grows one wrapper per slice.
  # Inline boundary contracts deliberately make this syscall port longer than the quality default.
  # rubocop:disable Metrics/ClassLength
  class SystemCalls
    extend T::Sig

    include FileTests
    include ProcessIdentity
    include ProcessControl
    include ResourceLimits

    COLLATION = T.let(Collation.new, Collation)

    # Run `file` as an external program with argv.first as the child's argv[0]
    # — for the ordinary $PATH search the caller passes the bare command name
    # as `file`; `command -p` passes its default-PATH resolution instead,
    # without renaming the command (dash-probed via `$0`). The [cmd, argv0]
    # form forbids the shell path even for a single-word command, so `spawn`
    # never re-interprets words.
    sig do
      params(file: String, env: T::Hash[String, String], argv: T::Array[String],
             options: T::Hash[T.any(Integer, Symbol), T.untyped]).returns(Integer)
    end
    def spawn(file, env, argv, options)
      # Sorbet rejects a dynamically sized non-terminal splat even for Ruby's variadic process API.
      T.unsafe(Process).spawn(env, [file, argv.first], *argv.drop(1), options)
    end

    # The system default PATH (confstr _CS_PATH): the search path `command -p`
    # uses, guaranteed to find the standard utilities regardless of $PATH.
    # POSIX defines _CS_PATH on every system; the coalesce only satisfies
    # confstr's nilable signature.
    sig { returns(String) }
    def default_path
      T.must(Etc.confstr(Etc::CS_PATH))
    end

    # Replace the current process image (the `exec` builtin); the [cmd, argv0]
    # form forbids the shell path, like #spawn. Returns only if the exec fails.
    sig do
      params(env: T::Hash[String, String], argv: T::Array[String],
             options: T::Hash[T.any(Integer, Symbol), T.untyped]).returns(T.noreturn)
    end
    def exec(env, argv, options)
      name = argv.first
      # The same intrinsic limitation as spawn; only the Process receiver crosses the escape hatch.
      T.unsafe(Process).exec(env, [name, name], *argv.drop(1), options)
    end

    # Accumulated CPU times for the `times` builtin: a Process::Tms with utime /
    # stime for the shell and cutime / cstime for its children. Non-deterministic,
    # so the builtin's output is verified by format rather than differentially.
    sig { returns(Process::Tms) }
    def times
      Process.times
    end

    # Send a signal to a process (the `kill` builtin); signal 0 only probes that
    # the target exists. Real signal delivery cannot run under the test harness.
    # :nocov:
    sig { params(signal: T.any(Integer, String), pid: Integer).returns(Integer) }
    def kill(signal, pid)
      Process.kill(signal, pid)
    end

    # Install a signal disposition for `trap`: a command string ('IGNORE' /
    # 'SYSTEM_DEFAULT') or, when nil, the block to run when the signal arrives. Mutating
    # the process's real signal handlers cannot run under the test harness.
    sig do
      params(name: String, command: T.nilable(String),
             block: T.nilable(T.proc.params(signal: Integer).returns(T.untyped))).returns(T.untyped)
    end
    def trap_signal(name, command, &block)
      Signal.trap(name, command || block)
    end
    # :nocov:

    sig { returns([IO, IO]) }
    def pipe
      IO.pipe
    end

    # Return a non-owning IO wrapper for an fd that is already open in the rush
    # process (typically inherited from the parent) but not tracked by IoTable.
    # A closed fd returns nil so redirection code can report "fd not open".
    # Unbuffered: every `n>&9` evaluation wraps the fd anew, and buffered
    # wrappers would flush at exit in GC order — reordering or hiding writes
    # (rush-erq: container-reversed lines; a `cat` mid-script saw nothing
    # where dash, which writes straight to the fd, showed the line).
    sig { params(fd: Integer).returns(T.nilable(IO)) }
    def inherited_fd(fd)
      stream = T.let(IO.new(fd, autoclose: false), IO)
      stream.sync = true
      stream
    rescue Errno::EBADF
      nil
    end

    # fork/exit! replace or split the process and so cannot run in-process under
    # the test harness; the child-side logic they drive is extracted into pure
    # methods that ARE tested, and real behaviour is covered by subprocess specs.
    # exit! flushes the standard streams first: $stdout is unbuffered only when a
    # tty, so a forked child running a builtin would otherwise lose its output.
    # :nocov:
    sig do
      params(blk: T.nilable(T.proc.void)).returns(T.nilable(Integer))
    end
    def fork(&blk)
      return Process.fork unless blk

      Process.fork(&blk)
    end

    sig { params(code: Integer).returns(T.noreturn) }
    def exit!(code)
      stdout.flush
      stderr.flush
      Process.exit!(code)
    end
    # :nocov:

    sig { params(path: String).returns(Integer) }
    def chdir(path)
      Dir.chdir(path)
    end

    sig { returns(String) }
    def pwd
      Dir.pwd
    end

    sig { params(path: String, base: String).returns(String) }
    def expand_path(path, base)
      File.expand_path(path, base)
    end

    sig do
      params(pattern: String, str: String, locale: T::Array[String]).returns(T::Boolean)
    end
    def fnmatch?(pattern, str, locale: COLLATION.default_settings)
      COLLATION.match_shell?(pattern, str, locale) { ShellPattern.new(pattern).match?(str) }
    end

    # Pathname expansion: libc filters widened Dir.glob candidates and orders
    # exact matches by LC_COLLATE; unsupported libcs retain the Ruby fallback.
    sig { params(pattern: String, locale: T::Array[String]).returns(T::Array[String]) }
    def glob(pattern, locale: COLLATION.default_settings)
      COLLATION.glob(pattern, locale) do
        shell_pattern = T.let(ShellPattern.new(pattern), ShellPattern)
        Dir.glob(shell_pattern.glob_source).grep(shell_pattern)
      end
    end

    # Sync so a builtin's write reaches the file immediately — like a pipe write
    # end (sync by default), this lets a forked subshell's output survive its
    # exit! and be visible to a later command. File.new, not File.open: the
    # redirection keeps the file open past this call — the caller owns the
    # handle until close_redirect releases it, so the auto-closing block form
    # would be wrong here.
    sig { params(path: String, mode: T.any(String, Integer)).returns(File) }
    def open_file(path, mode)
      io = T.let(File.new(path, mode), File)
      io.sync = true
      io
    end

    # Flush and release a file a redirection opened, so a later command in the
    # same shell sees the data and the fd does not leak.
    # Sorbet has no structural protocol equivalent to RBS `_IoStream`; keep this one parameter open.
    sig { params(io: T.untyped).void }
    def close_redirect(io)
      io.close
    end

    sig { params(path: String).returns(String) }
    def read_file(path)
      File.read(path)
    end

    # A readable stream carrying a here-document body (a real fd, via a tempfile,
    # so spawned children can read it).
    sig { params(body: String).returns(Tempfile) }
    def here_doc(body)
      file = T.let(Tempfile.new('rush-heredoc'), Tempfile)
      file.write(body)
      file.rewind
      file
    end

    sig { returns(IO) }
    def stdin
      T.let($stdin, IO)
    end

    sig { returns(IO) }
    def stdout
      T.let($stdout, IO)
    end

    sig { returns(IO) }
    def stderr
      T.let($stderr, IO)
    end

    # Interactive-REPL support: read one line of input (nil at EOF) and report
    # whether standard input / standard error are terminals (POSIX interactivity
    # requires both).
    sig { returns(T.nilable(String)) }
    def read_line
      stdin.gets
    end

    # Interactive line editing: Reline draws the prompt (on stderr, like the
    # plain path), records the line into its in-memory history, and returns nil
    # at EOF. A real-terminal path the test harness cannot drive; the Docker
    # gate's pty smoke exercises it.
    # :nocov:
    sig { params(prompt: String).returns(T.nilable(String)) }
    def edit_line(prompt)
      Reline.output = stderr
      Reline.readline(prompt, true)
    end
    # :nocov:

    sig { returns(T::Boolean) }
    def tty?
      stdin.tty?
    end

    sig { returns(T::Boolean) }
    def stderr_tty?
      stderr.tty?
    end

    # Home directory of a named user for ~user tilde expansion, or nil if there
    # is no such user.
    sig { params(name: String).returns(T.nilable(String)) }
    def home_dir(name)
      T.must(Etc.getpwnam(name)).dir
    rescue ArgumentError
      nil
    end
  end
  # rubocop:enable Metrics/ClassLength
end
