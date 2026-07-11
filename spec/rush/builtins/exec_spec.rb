# frozen_string_literal: true

RSpec.describe Rush::Builtins::Exec do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new('A' => '1')) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['exec', *args], io).call
  end

  it 'makes redirections permanent when given no command' do
    redirected = io.with(1, StringIO.new)
    expect(described_class.new(executor, ['exec'], redirected).call).to be_success
    expect(executor.io).to be(redirected)
  end

  it 'replaces the process with the command and the exported environment' do
    run('ls', '-l')
    expect(system.execed).to eq([{ 'A' => '1' }, ['ls', '-l'], io.to_spawn_options.merge(close_others: true)])
  end

  it 'includes the simple-command assignment environment in the replacement' do
    environment = { 'A' => '1', 'X' => 'temporary' }
    described_class.new(executor, %w[exec show], io, environment).call
    expect(system.execed.fetch(0)).to eq(environment)
  end

  it 'aborts the shell with 127 when the command is not found' do
    allow(system).to receive(:exec).and_raise(Errno::ENOENT)
    expect { run('nope') }.to raise_error(Rush::ExitSignal) { |e| expect(e.code).to eq(127) }
    expect(system.stderr.string).to eq("rush: nope: not found\n")
  end

  it 'aborts the shell with 126 when the command is not executable' do
    allow(system).to receive(:exec).and_raise(Errno::EACCES)
    expect { run('nope') }.to raise_error(Rush::ExitSignal) { |e| expect(e.code).to eq(126) }
    expect(system.stderr.string).to eq("rush: nope: Permission denied\n")
  end

  it 'keeps the exec failure status when stderr is closed' do
    allow(system).to receive(:exec).and_raise(Errno::ENOENT)
    closed = io.with_closed(2)
    expect { described_class.new(executor, %w[exec nope], closed).call }
      .to raise_error(Rush::ExitSignal) { |e| expect(e.code).to eq(127) }
    expect(system.stderr.string).to be_empty
  end
end
