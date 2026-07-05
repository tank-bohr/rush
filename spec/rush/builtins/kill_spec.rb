# frozen_string_literal: true

RSpec.describe Rush::Builtins::Kill do
  let(:system) { FakeSystemCalls.new(dead_pids: [999]) }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['kill', *args], io).call
  end

  it 'sends TERM by default to a pid' do
    expect(run('111')).to be_success
    expect(system.kills).to eq([['TERM', 111]])
  end

  it 'sends a named signal given as -SIG' do
    run('-INT', '111')
    expect(system.kills).to eq([['INT', 111]])
  end

  it 'sends a numbered signal straight to the OS' do
    run('-9', '111')
    expect(system.kills).to eq([[9, 111]])
  end

  it 'accepts multi-digit numbered signal specs' do
    expect(run('-15', '111')).to be_success
    expect(system.kills).to eq([[15, 111]])
  end

  it 'accepts the -s sigspec form' do
    expect(run('-s', 'HUP', '111')).to be_success
    expect(system.kills).to eq([['HUP', 111]])
  end

  it 'treats -0 as an existence probe (signal 0)' do
    expect(run('-0', '111')).to be_success
    expect(system.kills).to eq([[0, 111]])
  end

  it 'signals several pids' do
    run('-TERM', '111', '222')
    expect(system.kills).to eq([['TERM', 111], ['TERM', 222]])
  end

  it 'treats a bare - as a target rather than a signal flag (default TERM)' do
    expect(run(+'-', '111').exitstatus).to eq(1)
    expect(system.kills).to eq([['TERM', 111]])
    expect(system.stderr.string).to eq("kill: -: no such process\n")
  end

  it 'fails with 1 when the only target does not exist' do
    expect(run('-0', '999').exitstatus).to eq(1)
    expect(system.stderr.string).to eq("kill: 999: no such process\n")
  end

  it 'fails 1 if any target is missing while signalling the others' do
    expect(run('-0', '111', '999').exitstatus).to eq(1)
    expect(system.kills).to eq([[0, 111]])
    expect(system.stderr.string).to eq("kill: 999: no such process\n")
  end

  it 'rejects an unknown signal name with status 2 and sends nothing' do
    expect(run('-BADD', '111').exitstatus).to eq(2)
    expect(system.kills).to be_empty
    expect(system.stderr.string).to eq("kill: BADD: invalid signal specification\n")
  end

  it 'reports usage with status 2 when given no arguments' do
    expect(run.exitstatus).to eq(2)
    expect(system.stderr.string).to eq("kill: usage: kill [-s sigspec | -signum] pid ...\n")
  end

  it 'reports usage when a signal flag has no target' do
    expect(run('-TERM').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("kill: usage: kill [-s sigspec | -signum] pid ...\n")
  end

  it 'reports usage when -s has no sigspec and target' do
    expect(run('-s').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("kill: usage: kill [-s sigspec | -signum] pid ...\n")
  end

  it 'lists the signal name for a number with -l' do
    expect(run('-l', '15')).to be_success
    expect(system.stdout.string).to eq("TERM\n")
  end

  it 'ignores extra operands after the first -l argument' do
    expect(run('-l', '15', '9')).to be_success
    expect(system.stdout.string).to eq("TERM\n")
  end

  it 'maps a wait status (128 + signal) to its name with -l' do
    expect(run('-l', '143')).to be_success
    expect(system.stdout.string).to eq("TERM\n")
  end

  it 'handles the wait-status adjustment boundary for -l' do
    expect(run('-l', '129')).to be_success
    expect(system.stdout.string).to eq("HUP\n")
  end

  it 'rejects -l of zero with status 2' do
    expect(run('-l', '0').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("kill: 0: invalid signal specification\n")
  end

  it 'rejects -l of 128 with status 2' do
    expect(run('-l', '128').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("kill: 128: invalid signal specification\n")
  end

  it 'rejects -l of an out-of-range number with status 2' do
    expect(run('-l', '99').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("kill: 99: invalid signal specification\n")
  end

  it 'rejects -l of a non-numeric argument with status 2' do
    expect(run('-l', 'TERM').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("kill: TERM: invalid signal specification\n")
  end

  it 'rejects -l of a partially numeric argument with status 2' do
    expect(run('-l', '15x').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("kill: 15x: invalid signal specification\n")
  end

  it 'lists the known signal names with a bare -l' do
    expect(run('-l')).to be_success
    expect(system.stdout.string).to start_with("HUP\nINT\nQUIT\n").and end_with("SYS\n")
  end
end
