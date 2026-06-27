# frozen_string_literal: true

# In-memory stand-in for Rush::SystemCalls used by integration and builtin
# specs: stdin/stdout/stderr are StringIO, files open to in-memory buffers, and
# process-spawning paths are exercised separately with doubles. Nothing here
# touches the real OS.
class FakeSystemCalls
  attr_reader :stdin, :stdout, :stderr, :files, :chdirs, :pwd, :kills, :traps_installed

  UNTRAPPABLE = %w[KILL STOP].freeze

  NODE_DEFAULTS = { type: :file, size: 1, readable: true, writable: true,
                    executable: false, symlink: false }.freeze

  # rubocop:disable Metrics/ParameterLists -- a test double accrues config knobs
  def initialize(stdin: '', pwd: '/home/test', tty: false, homes: {}, globs: {}, dead_pids: [])
    @stdin = StringIO.new(stdin)
    @stdout = StringIO.new
    @stderr = StringIO.new
    @pwd = pwd
    @tty = tty
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
  end

  # Configured matches for a pattern; unconfigured patterns match nothing, so
  # ordinary words pass through as literals (mirroring no-match behaviour).
  def glob(pattern) = @globs.fetch(pattern, [])

  def read_line = @stdin.gets

  def tty? = @tty

  # Records the signal sent; a pid listed in dead_pids raises like a real kill
  # to a missing process, so the builtin's failure path is exercised.
  def kill(signal, pid)
    raise Errno::ESRCH if @dead_pids.include?(pid)

    @kills << [signal, pid]
  end

  # Records the installed disposition and keeps the handler block so specs can
  # invoke it; KILL/STOP raise like the real OS to exercise the keep-anyway path.
  def trap_signal(name, command, &block)
    raise Errno::EINVAL if UNTRAPPABLE.include?(name)

    @traps_installed << [name, command]
    @trap_blocks[name] = block
  end

  def trap_block(name) = @trap_blocks[name]

  def home_dir(name) = @homes[name]

  # Register an in-memory node for the file-test predicates below.
  def register(path, **attrs) = @nodes[path] = NODE_DEFAULTS.merge(attrs)

  def exist?(path) = @nodes.key?(path)

  def file?(path) = node(path, :type) == :file

  def directory?(path) = node(path, :type) == :dir

  def readable?(path) = node(path, :readable) == true

  def writable?(path) = node(path, :writable) == true

  def executable?(path) = node(path, :executable) == true

  def file_nonempty?(path) = node(path, :size).to_i.positive?

  def symlink?(path) = node(path, :symlink) == true

  def expand_path(path, base) = File.expand_path(path, base)

  def fnmatch(pattern, str) = File.fnmatch(pattern, str, File::FNM_DOTMATCH)

  def open_file(path, _mode) = (@files[path] = StringIO.new)

  # Seed a readable file (for the `.` builtin); read_file raises if absent.
  def provide_file(path, body) = @contents[path] = body

  def read_file(path) = @contents.fetch(path) { raise Errno::ENOENT, path }

  def here_doc(body) = StringIO.new(body)

  # Records an exec instead of replacing the process, so specs can assert it.
  attr_reader :execed

  def exec(env, argv, options) = (@execed = [env, argv, options])

  # Pipeline plumbing: present so specs can stub them (verify_partial_doubles);
  # the defaults are unused because the orchestration tests override them.
  def pipe = [StringIO.new, StringIO.new]

  def fork(&) = nil

  def waitpid2(pid) = [pid, nil]

  def chdir(path)
    raise @chdir_error if @chdir_error

    @chdirs << path
  end

  def fail_chdir_with(error)
    @chdir_error = error
  end

  private

  def node(path, key) = @nodes.fetch(path, {})[key]
end
