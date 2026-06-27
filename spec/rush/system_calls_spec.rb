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

  it 'delegates directory operations' do
    allow(Dir).to receive(:chdir).with('/x')
    allow(Dir).to receive(:pwd).and_return('/here')
    system.chdir('/x')
    expect(system.pwd).to eq('/here')
    expect(Dir).to have_received(:chdir).with('/x')
  end

  it 'expands paths and opens files' do
    expect(system.expand_path('a', '/base')).to eq('/base/a')
    allow(File).to receive(:open).with('/f', 'w').and_return(:io)
    expect(system.open_file('/f', 'w')).to eq(:io)
  end

  it 'exposes the standard streams' do
    expect(system.stdin).to be($stdin)
    expect(system.stdout).to be($stdout)
    expect(system.stderr).to be($stderr)
  end
end
