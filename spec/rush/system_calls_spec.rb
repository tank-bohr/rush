# frozen_string_literal: true

RSpec.describe Rush::SystemCalls do
  subject(:system) { described_class.new }

  describe '#spawn' do
    it 'execs argv without a shell using the [cmd, argv0] form' do
      allow(Process).to receive(:spawn).and_return(99)
      expect(system.spawn({ 'A' => '1' }, %w[ls -l], {})).to eq(99)
      expect(Process).to have_received(:spawn).with({ 'A' => '1' }, %w[ls ls], '-l', {})
    end
  end

  describe '#waitpid2' do
    it 'delegates to Process.waitpid2' do
      allow(Process).to receive(:waitpid2).with(7).and_return([7, :status])
      expect(system.waitpid2(7)).to eq([7, :status])
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
    allow(File).to receive(:open).with('/f', 'w').and_return(io)
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

  it 'matches glob patterns with fnmatch' do
    expect([system.fnmatch('a*', 'abc'), system.fnmatch('a*', 'xyz')]).to eq([true, false])
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

  it 'expands a glob pattern through Dir.glob' do
    allow(Dir).to receive(:glob).with('*.rb').and_return(['a.rb'])
    expect(system.glob('*.rb')).to eq(['a.rb'])
  end

  it 'reports accumulated CPU times through Process.times' do
    allow(Process).to receive(:times).and_return(:tms)
    expect(system.times).to eq(:tms)
  end

  it 'delegates umask and resource-limit syscalls' do
    allow(File).to receive(:umask) { |*args| args.empty? ? 0o022 : 0o077 }
    allow(Process).to receive(:getrlimit).with(Process::RLIMIT_NOFILE).and_return([1024, 4096])
    allow(Process).to receive(:setrlimit).with(Process::RLIMIT_NOFILE, 64, 128)

    expect([system.current_umask, system.change_umask(0o077), system.infinity_limit]).to eq([0o022, 0o077,
                                                                                             Process::RLIM_INFINITY])
    expect(system.getrlimit(:nofile)).to eq([1024, 4096])
    system.setrlimit(:nofile, 64, 128)
    expect(Process).to have_received(:setrlimit).with(Process::RLIMIT_NOFILE, 64, 128)
  end

  it 'treats unavailable resource limits as infinite and unsettable' do
    stub_const('Rush::SystemCalls::ResourceLimits::RLIMITS', missing: nil)

    expect(system.getrlimit(:missing)).to eq([system.infinity_limit, system.infinity_limit])
    expect { system.setrlimit(:missing, 1, 2) }.to raise_error(Errno::EINVAL)
  end
end
