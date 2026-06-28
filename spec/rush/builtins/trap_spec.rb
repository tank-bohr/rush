# frozen_string_literal: true

RSpec.describe Rush::Builtins::Trap do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['trap', *args], io).call
  def traps = state.traps

  it 'sets an action for a signal' do
    run('echo hi', 'INT')
    expect(traps.action('INT')).to eq('echo hi')
  end

  it 'sets one action for several signals at once' do
    run('cleanup', 'INT', 'TERM')
    expect([traps.action('INT'), traps.action('TERM')]).to eq(%w[cleanup cleanup])
  end

  it 'records signal 0 under the EXIT name' do
    run('bye', '0')
    expect(traps.action('EXIT')).to eq('bye')
  end

  it 'ignores a signal given an empty action' do
    run('', 'INT')
    expect(traps.action('INT')).to eq('')
  end

  it 'resets a signal given a "-" action' do
    run('x', 'INT')
    run('-', 'INT')
    expect(traps.action('INT')).to be_nil
  end

  it 'treats a lone signal operand as a reset, consuming no action' do
    run('x', 'INT')
    run('INT')
    expect(traps.action('INT')).to be_nil
  end

  it 'lists active traps as quoted lines ordered by signal number' do
    run('a', 'TERM')
    run('b', 'INT')
    run('c', 'EXIT')
    run
    expect(system.stdout.string).to eq("trap -- 'c' EXIT\ntrap -- 'b' INT\ntrap -- 'a' TERM\n")
  end

  it 'quotes an embedded single quote dash-style when listing' do
    run("echo a'b", 'INT')
    run
    expect(system.stdout.string).to eq(%(trap -- 'echo a'"'"'b' INT\n))
  end

  it 'reports a bad signal, applies the signals before it and stops with status 1' do
    status = run('x', 'INT', 'BADD', 'TERM')
    expect(status.exitstatus).to eq(1)
    expect(system.stderr.string).to eq("trap: BADD: bad trap\n")
    expect([traps.action('INT'), traps.action('TERM')]).to eq(['x', nil])
  end

  it 'succeeds and prints nothing when listing an empty trap table' do
    expect([run.exitstatus, system.stdout.string]).to eq([0, ''])
  end

  it 'installs a handler disposition for a real signal' do
    run('echo hi', 'INT')
    expect(system.traps_installed).to eq([['INT', nil]])
  end

  it 'installs IGNORE for an ignored signal and DEFAULT on reset' do
    run('', 'INT')
    run('-', 'INT')
    expect(system.traps_installed).to eq([%w[INT IGNORE], %w[INT DEFAULT]])
  end

  it 'does not install an OS handler for the EXIT pseudo-signal' do
    run('bye', 'EXIT')
    run('-', 'EXIT')
    expect(system.traps_installed).to be_empty
  end

  it 'keeps a trap on an untrappable signal that cannot be installed' do
    run('echo x', 'KILL')
    expect(traps.action('KILL')).to eq('echo x')
  end

  it 'runs the action and restores $? when the signal is delivered' do
    state.record_status(Rush::Status.failure(7))
    run('echo caught', 'TERM')
    system.trap_block('TERM').call
    expect([system.stdout.string, state.last_status.exitstatus]).to eq(["caught\n", 7])
  end
end
