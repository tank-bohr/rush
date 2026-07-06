# frozen_string_literal: true

# In-memory stand-in for Rush::SystemCalls used by integration and builtin
# specs: stdin/stdout/stderr are StringIO, files open to in-memory buffers, and
# process-spawning paths are exercised separately with doubles. Nothing here
# touches the real OS.
class FakeSystemCalls
  attr_reader :stdin, :stdout, :stderr, :files, :chdirs, :pwd, :kills, :traps_installed, :limits_set
  attr_accessor :wait_status

  UNTRAPPABLE = %w[KILL STOP].freeze

  # A Process::Status stand-in: fork is a no-op so no child truly runs, and a
  # spec sets `wait_status` to control the status a command substitution sees.
  ChildStatus = Struct.new(:exitstatus) do
    def termsig
      nil
    end
  end

  # A Process::Tms stand-in for the `times` builtin; zeros keep the format
  # deterministic (the real times are non-deterministic).
  ProcessTimes = Struct.new(:utime, :stime, :cutime, :cstime)

  NODE_DEFAULTS = { type: :file, size: 1, readable: true, writable: true,
                    executable: false, symlink: false }.freeze

  # rubocop:disable Metrics/ParameterLists -- a test double accrues config knobs
  def initialize(stdin: '', pwd: '/home/test', tty: false, stderr_tty: nil, homes: {}, globs: {}, dead_pids: [])
    @stdin = StringIO.new(stdin)
    @stdout = StringIO.new
    @stderr = StringIO.new
    @pwd = pwd
    @tty = tty
    @stderr_tty = stderr_tty.nil? ? tty : stderr_tty
    @homes = homes
    @globs = globs
    @dead_pids = dead_pids
    setup_registries
  end
  # rubocop:enable Metrics/ParameterLists

  def setup_registries
    @kills = []
    @traps_installed = []
    @trap_blocks = {}
    @files = {}
    @chdirs = []
    @chdir_error = nil
    @nodes = {}
    @contents = {}
    @wait_status = ChildStatus.new(0)
    @inherited_fds = {}
    @umask = 0o022
    @limits = default_limits
    @limits_set = []
  end

  def inherit_fd(fd, stream)
    @inherited_fds[fd] = stream
  end

  def inherited_fd(fd)
    @inherited_fds.fetch(fd, nil)
  end

  # Configured matches for a pattern; unconfigured patterns match nothing, so
  # ordinary words pass through as literals (mirroring no-match behaviour).
  def glob(pattern)
    @globs.fetch(pattern, [])
  end

  def read_line
    @stdin.gets
  end

  def tty?
    @tty
  end

  def stderr_tty?
    @stderr_tty
  end

  def pid
    4242
  end

  def ppid
    3131
  end

  # Records the signal sent; a pid listed in dead_pids raises like a real kill
  # to a missing process, so the builtin's failure path is exercised.
  def kill(signal, pid)
    raise Errno::ESRCH if @dead_pids.include?(pid)

    @kills << [signal, pid]
    1
  end

  # Records the installed disposition and keeps the handler block so specs can
  # invoke it; KILL/STOP raise like the real OS to exercise the keep-anyway path.
  def trap_signal(name, command, &block)
    raise Errno::EINVAL if UNTRAPPABLE.include?(name)

    @traps_installed << [name, command]
    @trap_blocks[name] = block
  end

  def trap_block(name)
    @trap_blocks.fetch(name, nil)
  end

  def home_dir(name)
    @homes.fetch(name, nil)
  end

  # Register an in-memory node for the file-test predicates below.
  def register(path, **attrs)
    @nodes[path] = NODE_DEFAULTS.merge(attrs)
  end

  def exist?(path)
    @nodes.key?(path)
  end

  def file?(path)
    node(path, :type) == :file
  end

  def directory?(path)
    node(path, :type) == :dir
  end

  def readable?(path)
    node(path, :readable) == true
  end

  def writable?(path)
    node(path, :writable) == true
  end

  def executable?(path)
    node(path, :executable) == true
  end

  def file_nonempty?(path)
    node(path, :size).to_i.positive?
  end

  def symlink?(path)
    node(path, :symlink) == true
  end

  def expand_path(path, base)
    File.expand_path(path, base)
  end

  def fnmatch(pattern, str)
    File.fnmatch(pattern, str, File::FNM_DOTMATCH)
  end

  def open_file(path, _mode)
    (@files[path] = StringIO.new)
  end

  # The in-memory StringIO needs no real close; leaving it open keeps `.string`
  # readable so specs can assert what a redirection wrote.
  def close_redirect(_io)
    nil
  end

  # Seed a readable file (for the `.` builtin); read_file raises if absent.
  def provide_file(path, body)
    @contents[path] = body
  end

  def read_file(path)
    @contents.fetch(path) { raise Errno::ENOENT, path }
  end

  def here_doc(body)
    StringIO.new(body)
  end

  def times
    ProcessTimes.new(0.0, 0.0, 0.0, 0.0)
  end

  def current_umask
    @umask
  end

  def change_umask(mask)
    @umask = mask
  end

  def infinity_limit
    1 << 62
  end

  def getrlimit(resource)
    @limits.fetch(resource)
  end

  def setrlimit(resource, soft, hard)
    @limits[resource] = [soft, hard]
    @limits_set << [resource, soft, hard]
  end

  # Records an exec instead of replacing the process, so specs can assert it.
  attr_reader :execed

  def exec(env, argv, options)
    (@execed = [env, argv, options])
  end

  # Pipeline plumbing: present so specs can stub them (verify_partial_doubles);
  # the defaults are unused because the orchestration tests override them.
  def pipe
    [StringIO.new, StringIO.new]
  end

  def fork
    nil
  end

  def waitpid2(pid)
    [pid, @wait_status]
  end

  def chdir(path)
    raise @chdir_error if @chdir_error

    @chdirs << path
  end

  def fail_chdir_with(error)
    @chdir_error = error
  end

  private

  def default_limits
    {
      cpu: [infinity_limit, infinity_limit], fsize: [infinity_limit, infinity_limit],
      data: [infinity_limit, infinity_limit], stack: [8192 * 1024, infinity_limit],
      core: [infinity_limit, infinity_limit], rss: [infinity_limit, infinity_limit],
      memlock: [8192 * 1024, 8192 * 1024], nproc: [4096, 4096], nofile: [1024, 4096],
      as: [infinity_limit, infinity_limit], locks: [infinity_limit, infinity_limit], rtprio: [0, 0]
    }
  end

  def node(path, key)
    attrs = @nodes.fetch(path, {})
    attrs.fetch(key, nil)
  end
end
