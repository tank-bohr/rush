# frozen_string_literal: true

# In-memory stand-in for Rush::SystemCalls used by integration and builtin
# specs: stdin/stdout/stderr are StringIO, files open to in-memory buffers, and
# process-spawning paths are exercised separately with doubles. Nothing here
# touches the real OS.
class FakeSystemCalls
  attr_reader :stdin, :stdout, :stderr, :files, :chdirs, :pwd

  NODE_DEFAULTS = { type: :file, size: 1, readable: true, writable: true,
                    executable: false, symlink: false }.freeze

  def initialize(stdin: '', pwd: '/home/test')
    @stdin = StringIO.new(stdin)
    @stdout = StringIO.new
    @stderr = StringIO.new
    @pwd = pwd
    @files = {}
    @chdirs = []
    @chdir_error = nil
    @nodes = {}
    @contents = {}
  end

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
