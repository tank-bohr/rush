# frozen_string_literal: true

RSpec.describe Rush::SystemCalls do
  subject(:system) { described_class.new }

  describe '#spawn' do
    it 'execs argv without a shell using the [cmd, argv0] form' do
      allow(Process).to receive(:spawn).and_return(99)
      expect(system.spawn('ls', { 'A' => '1' }, %w[ls -l], {})).to eq(99)
      expect(Process).to have_received(:spawn).with({ 'A' => '1' }, %w[ls ls], '-l', {})
    end

    it 'execs an explicit file while argv[0] keeps the command name (command -p)' do
      allow(Process).to receive(:spawn).and_return(99)
      system.spawn('/bin/ls', {}, %w[ls -l], {})
      expect(Process).to have_received(:spawn).with({}, ['/bin/ls', 'ls'], '-l', {})
    end
  end

  describe '#default_path' do
    it 'asks confstr for the system default PATH (the command -p search path)' do
      allow(Etc).to receive(:confstr).with(Etc::CS_PATH).and_return('/bin:/usr/bin')
      expect(system.default_path).to eq('/bin:/usr/bin')
    end
  end

  describe '#waitpid2' do
    it 'delegates to Process.waitpid2' do
      allow(Process).to receive(:waitpid2).with(7).and_return([7, :status])
      expect(system.waitpid2(7)).to eq([7, :status])
    end
  end

  describe '#wait_stoppable' do
    it 'waits WUNTRACED, so a stopped child answers too' do
      allow(Process).to receive(:waitpid2).with(7, Process::WUNTRACED).and_return([7, :stopped])
      expect(system.wait_stoppable(7)).to eq([7, :stopped])
    end
  end

  describe '#poll_child / #poll_pid / #poll_stopped / #poll_pid_stopped' do
    it 'polls WNOHANG, adding WUNTRACED only for the monitor-mode forms' do
      allow(Process).to receive(:waitpid2).and_return(nil)
      system.poll_child
      system.poll_pid(7)
      expect(Process).to have_received(:waitpid2).with(-1, Process::WNOHANG)
      expect(Process).to have_received(:waitpid2).with(7, Process::WNOHANG)
      system.poll_stopped
      system.poll_pid_stopped(7)
      flags = Process::WNOHANG | Process::WUNTRACED
      expect(Process).to have_received(:waitpid2).with(-1, flags)
      expect(Process).to have_received(:waitpid2).with(7, flags)
    end
  end

  describe '#ppid / #program_name' do
    it 'delegates the parent pid and the invocation name' do
      allow(Process).to receive(:ppid).and_return(77)
      expect(system.ppid).to eq(77)
      expect(system.program_name).to eq($PROGRAM_NAME)
    end
  end

  describe '#pgrp' do
    it 'reports the process group through Process.getpgrp' do
      expect(system.pgrp).to eq(Process.getpgrp)
    end
  end

  describe '#job_control_supported?' do
    it 'holds on every unix and drops only on Windows builds' do
      verdicts = %w[linux-gnu darwin24 freebsd14 solaris2.11 mswin64 mingw32 cygwin].map do |host|
        stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_os' => host))
        system.job_control_supported?
      end
      expect(verdicts).to eq([true, true, true, true, false, false, false])
    end
  end

  describe '#terminal_family' do
    it 'knows the ioctl vocabulary of every platform rush develops on' do
      expect(system.terminal_family).not_to be_nil
    end

    it 'maps host_os onto the linux and BSD ioctl code tables' do
      families = %w[linux-gnu darwin24 freebsd14 dragonfly].map do |host|
        stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_os' => host))
        system.terminal_family
      end
      expect(families).to eq(%i[linux bsd bsd bsd])
    end

    it 'admits no vocabulary for an unknown unix (job control degrades to grouping-only)' do
      stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_os' => 'solaris2.11'))
      expect(system.terminal_family).to be_nil
    end
  end

  describe '#exec' do
    it 'replaces the process via Process.exec using the [cmd, argv0] form' do
      allow(Process).to receive(:exec)
      system.exec({ 'A' => '1' }, %w[ls -l], { close_others: true })
      expect(Process).to have_received(:exec).with({ 'A' => '1' }, %w[ls ls], '-l', { close_others: true })
    end
  end

  it 'creates a pipe and reports the process id' do
    allow(IO).to receive(:pipe).and_return(%i[r w])
    allow(Process).to receive(:pid).and_return(321)
    expect([system.pipe, system.pid]).to eq([%i[r w], 321])
  end

  it 'wraps an already-open fd without owning it' do
    Tempfile.create('rush-fd') do |file|
      inherited = system.inherited_fd(file.fileno)
      inherited.write('x')
      inherited.flush
      file.rewind
      expect([inherited.fileno, file.read]).to eq([file.fileno, 'x'])
    end
  end

  it 'wraps inherited fds unbuffered, so wrappers never reorder or delay writes (rush-erq)' do
    Tempfile.create('rush-fd') do |file|
      system.inherited_fd(file.fileno).write("one\n")
      system.inherited_fd(file.fileno).write("two\n")
      expect([system.inherited_fd(file.fileno).sync, File.read(file.path)]).to eq([true, "one\ntwo\n"])
    end
  end

  it 'returns nil for a closed or negative inherited fd probe' do
    file = Tempfile.new('rush-fd')
    fd = file.fileno
    file.close!
    expect([system.inherited_fd(fd), system.inherited_fd(-1)]).to eq([nil, nil])
  end

  it 'delegates directory operations' do
    allow(Dir).to receive(:chdir).with('/x')
    allow(Dir).to receive(:pwd).and_return('/here')
    system.chdir('/x')
    expect(system.pwd).to eq('/here')
    expect(Dir).to have_received(:chdir).with('/x')
  end

  it 'expands paths and opens files in sync mode' do
    expect(system.expand_path('a', '/base')).to eq('/base/a')
    io = instance_double(File, :sync= => true)
    allow(File).to receive(:new).with('/f', 'w').and_return(io)
    expect(system.open_file('/f', 'w')).to be(io)
    expect(io).to have_received(:sync=).with(true)
  end

  it 'closes a redirect file through IO#close' do
    io = instance_double(File, close: nil)
    system.close_redirect(io)
    expect(io).to have_received(:close)
  end

  it 'reads a file through File.read' do
    allow(File).to receive(:read).with('/f').and_return('body')
    expect(system.read_file('/f')).to eq('body')
  end

  it 'builds a here-document stream through a rewound tempfile' do
    file = instance_double(Tempfile, write: nil, rewind: nil)
    allow(Tempfile).to receive(:new).with('rush-heredoc').and_return(file)
    expect(system.here_doc('body')).to be(file)
    expect(file).to have_received(:write).with('body')
    expect(file).to have_received(:rewind)
  end

  it 'matches ordinary and POSIX-class patterns with fnmatch' do
    expect([system.fnmatch?('a*', 'abc'), system.fnmatch?('a*', 'xyz'),
            system.fnmatch?('[[:alpha:]]', 'a'), system.fnmatch?('[[:digit:]]', 'a')])
      .to eq([true, false, true, false])
  end

  it 'falls back to the Ruby shell pattern when the collation backend declines fnmatch' do
    allow(Rush::SystemCalls::COLLATION).to receive(:match_shell?) { |*_args, &fallback| fallback.call }

    expect(system.fnmatch?('a[bc]d', 'abd')).to be(true)
    expect(system.fnmatch?('a[bc]d', 'aed')).to be(false)
  end

  it 'globs by pathname expansion through the collation backend under the C locale' do
    Dir.mktmpdir do |dir|
      %w[ab.txt ac.txt ad.md].each { |name| File.write(File.join(dir, name), '') }

      expect(system.glob("#{dir}/a[bc]*", locale: %w[C C]))
        .to eq([File.join(dir, 'ab.txt'), File.join(dir, 'ac.txt')])
    end
  end

  it 'falls back to widened Dir.glob results filtered by the shell pattern' do
    allow(Rush::SystemCalls::COLLATION).to receive(:glob) { |*_args, &fallback| fallback.call }

    Dir.mktmpdir do |dir|
      %w[ab.txt ac.txt ad.md].each { |name| File.write(File.join(dir, name), '') }

      expect(system.glob("#{dir}/a[bc]*")).to contain_exactly(
        File.join(dir, 'ab.txt'), File.join(dir, 'ac.txt')
      )
    end
  end

  it 'delegates stat-style file tests to File' do
    allow(File).to receive_messages(exist?: true, file?: true, directory?: true, symlink?: true, size?: 10)
    expect([system.exist?('/f'), system.file?('/f'), system.directory?('/d'),
            system.symlink?('/l'), system.file_nonempty?('/f')]).to all(be(true))
  end

  it 'delegates access file tests to File' do
    allow(File).to receive_messages(readable?: true, writable?: false, executable?: true)
    expect([system.readable?('/f'), system.executable?('/f')]).to all(be(true))
    expect(system.writable?('/f')).to be(false)
  end

  it 'delegates file-type and mode-bit tests to File' do
    allow(File).to receive_messages(pipe?: true, blockdev?: true, chardev?: true,
                                    socket?: true, setgid?: true, setuid?: true)
    expect([system.pipe?('/p'), system.blockdev?('/b'), system.chardev?('/c'),
            system.socket?('/s'), system.setgid?('/g'), system.setuid?('/u')]).to all(be(true))
  end

  it 'answers tty_fd? by wrapping the descriptor without autoclose' do
    io = instance_double(IO, tty?: true)
    allow(IO).to receive(:new).with(5, autoclose: false).and_return(io)
    expect(system.tty_fd?(5)).to be(true)
  end

  it 'treats an unusable descriptor number as not a terminal' do
    allow(IO).to receive(:new).and_raise(Errno::EBADF)
    expect(system.tty_fd?(27)).to be(false)
  end

  it 'exposes the standard streams' do
    expect(system.stdin).to be($stdin)
    expect(system.stdout).to be($stdout)
    expect(system.stderr).to be($stderr)
  end

  it 'reads a line of input and reports terminal status via stdin' do
    allow($stdin).to receive_messages(gets: "line\n", tty?: true)
    expect([system.read_line, system.tty?]).to eq(["line\n", true])
  end

  it 'reports terminal status of stderr separately' do
    allow($stderr).to receive(:tty?).and_return(true)
    expect(system.stderr_tty?).to be(true)
  end

  it 'reports root privileges from the effective uid' do
    allow(Process).to receive(:euid).and_return(0)
    expect(system.privileged?).to be(true)
  end

  it 'retries a wait interrupted by the interactive SIGINT handler' do
    calls = 0
    allow(Process).to receive(:waitpid2) do
      calls += 1
      raise Rush::Interrupted, 'interrupted' if calls == 1

      [7, :reaped]
    end
    expect(system.waitpid2(7)).to eq([7, :reaped])
  end

  it 'looks up a user home directory, returning nil for an unknown user' do
    allow(Etc).to receive(:getpwnam).with('bob').and_return(instance_double(Etc::Passwd, dir: '/home/bob'))
    allow(Etc).to receive(:getpwnam).with('ghost').and_raise(ArgumentError)
    expect([system.home_dir('bob'), system.home_dir('ghost')]).to eq(['/home/bob', nil])
  end

  it 'expands an ordinary glob pattern through Dir.glob' do
    allow(Dir).to receive(:glob).with('*.rb', sort: false).and_return(['a.rb'])
    expect(system.glob('*.rb')).to eq(['a.rb'])
  end

  it 'widens POSIX brackets for glob discovery and filters the candidates' do
    allow(Dir).to receive(:glob).with('file*', sort: false).and_return(%w[file1 filea filex])

    expect([system.glob('file[[:digit:]]'), system.glob('file[[=a=]]'), system.glob('file[[.x.]]')])
      .to eq([['file1'], ['filea'], ['filex']])
  end

  it 'reports accumulated CPU times through Process.times' do
    allow(Process).to receive(:times).and_return(:tms)
    expect(system.times).to eq(:tms)
  end

  it 'delegates umask and resource-limit syscalls' do
    allow(File).to receive(:umask) { |*args| args.empty? ? 0o022 : 0o011 }
    allow(Process).to receive(:getrlimit).with(Process::RLIMIT_NOFILE).and_return([1024, 4096])
    allow(Process).to receive(:setrlimit).with(Process::RLIMIT_NOFILE, 64, 128)

    expect([system.current_umask, system.change_umask(0o077), system.infinity_limit]).to eq([0o022, 0o011,
                                                                                             Process::RLIM_INFINITY])
    expect(File).to have_received(:umask).with(0o077)
    expect(system.getrlimit(:nofile)).to eq([1024, 4096])
    expect(system.setrlimit(:nofile, 64, 128)).to be_nil
    expect(Process).to have_received(:setrlimit).with(Process::RLIMIT_NOFILE, 64, 128)
  end

  it 'normalizes every platform resource constant to an integer or nil' do
    limits = Rush::SystemCalls::ResourceLimits::RLIMITS
    expected_locks = Process.const_get(:RLIMIT_LOCKS) if Process.const_defined?(:RLIMIT_LOCKS)
    expect([limits.fetch(:locks), limits.values.all? { |value| value.nil? || value.is_a?(Integer) }])
      .to eq([expected_locks, true])
  end

  it 'treats unavailable resource limits as infinite and unsettable' do
    stub_const('Rush::SystemCalls::ResourceLimits::RLIMITS', missing: nil)

    expect(system.getrlimit(:missing)).to eq([system.infinity_limit, system.infinity_limit])
    expect { system.setrlimit(:missing, 1, 2) }.to raise_error(Errno::EINVAL)
  end
end
