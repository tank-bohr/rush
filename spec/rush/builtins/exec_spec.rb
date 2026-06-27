# frozen_string_literal: true

RSpec.describe Rush::Builtins::Exec do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new('A' => '1')) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['exec', *args], io).call

  it 'makes redirections permanent when given no command' do
    redirected = io.with(1, StringIO.new)
    expect(described_class.new(executor, ['exec'], redirected).call).to be_success
    expect(executor.io).to be(redirected)
  end

  it 'replaces the process with the command and the exported environment' do
    run('ls', '-l')
    expect(system.execed).to eq([{ 'A' => '1' }, ['ls', '-l'], io.to_spawn_options.merge(close_others: true)])
  end

  it 'aborts the shell with 127 when the command is not found' do
    allow(system).to receive(:exec).and_raise(Errno::ENOENT)
    expect { run('nope') }.to raise_error(Rush::ExitSignal) { |e| expect(e.code).to eq(127) }
  end

  it 'aborts the shell with 126 when the command is not executable' do
    allow(system).to receive(:exec).and_raise(Errno::EACCES)
    expect { run('nope') }.to raise_error(Rush::ExitSignal) { |e| expect(e.code).to eq(126) }
  end
end
