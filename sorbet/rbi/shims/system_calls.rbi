# typed: true
# frozen_string_literal: true

# Hand-written shim: SystemCalls is kept `# typed: false` because a few Ruby
# syscall forms are beyond Sorbet's static model, but callers still benefit from
# the public port's typed surface.
module Rush
  # Public static surface for the typed callers of the impure syscall port.
  class SystemCalls
    sig do
      params(file: String, env: T::Hash[String, String], argv: T::Array[String], options: T.untyped)
        .returns(Integer)
    end
    def spawn(file, env, argv, options); end

    sig { returns(String) }
    def default_path; end

    sig { params(pid: Integer).returns([Integer, Process::Status]) }
    def waitpid2(pid); end

    sig { params(env: T::Hash[String, String], argv: T::Array[String], options: T.untyped).returns(T.untyped) }
    def exec(env, argv, options); end

    sig { returns(Integer) }
    def pid; end

    sig { returns(Process::Tms) }
    def times; end

    sig { params(signal: T.untyped, pid: Integer).returns(Integer) }
    def kill(signal, pid); end

    sig do
      params(name: String, command: T.nilable(String),
             block: T.proc.params(arg0: T.untyped).returns(T.untyped)).returns(T.untyped)
    end
    def trap_signal(name, command, &block); end

    sig { returns([IO, IO]) }
    def pipe; end

    sig { params(blk: T.proc.void).returns(T.nilable(Integer)) }
    def fork(&blk); end

    sig { params(code: Integer).returns(T.untyped) }
    def exit!(code); end

    sig { params(path: String).returns(Integer) }
    def chdir(path); end

    sig { returns(String) }
    def pwd; end

    sig { params(path: String, base: String).returns(String) }
    def expand_path(path, base); end

    sig { params(pattern: String, str: String, locale: T::Array[String]).returns(T::Boolean) }
    def fnmatch?(pattern, str, locale: T.unsafe(nil)); end

    sig { params(pattern: String, locale: T::Array[String]).returns(T::Array[String]) }
    def glob(pattern, locale: T.unsafe(nil)); end

    sig { params(path: String, mode: T.any(String, Integer)).returns(File) }
    def open_file(path, mode); end

    sig { params(io: T.untyped).void }
    def close_redirect(io); end

    sig { params(path: String).returns(String) }
    def read_file(path); end

    sig { params(body: String).returns(Tempfile) }
    def here_doc(body); end

    sig { returns(IO) }
    def stdin; end

    sig { returns(IO) }
    def stdout; end

    sig { returns(IO) }
    def stderr; end

    sig { returns(T.nilable(String)) }
    def read_line; end

    sig { returns(T::Boolean) }
    def tty?; end

    sig { params(name: String).returns(T.nilable(String)) }
    def home_dir(name); end

    sig { returns(Integer) }
    def current_umask; end

    sig { params(mask: Integer).returns(Integer) }
    def change_umask(mask); end

    sig { returns(Integer) }
    def infinity_limit; end

    sig { params(resource: Symbol).returns([Integer, Integer]) }
    def getrlimit(resource); end

    sig { params(resource: Symbol, soft: Integer, hard: Integer).returns(NilClass) }
    def setrlimit(resource, soft, hard); end
  end
end
