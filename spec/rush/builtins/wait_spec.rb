# frozen_string_literal: true

RSpec.describe Rush::Builtins::Wait do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['wait', *args], io).call
  end

  def launch(pid, exitstatus)
    executor.jobs.record(pid)
    system.provide_child(pid, exitstatus)
  end

  it 'succeeds with no operands after collecting every background job' do
    launch(9, 4)
    expect(run).to be_success
    expect(run('9').exitstatus).to eq(4)
  end

  it 'returns the status of a background job pid' do
    launch(9, 5)
    expect(run('9').exitstatus).to eq(5)
  end

  it 'returns the last operand status across several pids' do
    launch(9, 3)
    launch(11, 5)
    expect(run('9', '11').exitstatus).to eq(5)
  end

  it 'treats an unknown pid as one that exited 127, silently' do
    expect(run('99999').exitstatus).to eq(127)
    expect(system.stderr.string).to be_empty
  end

  it 'gives an unknown last operand its 127 even after a known one (POSIX; dash keeps 3)' do
    launch(9, 3)
    expect(run('9', '99999').exitstatus).to eq(127)
  end

  it 'lets a known last operand overrule an earlier unknown one' do
    launch(9, 3)
    expect(run('99999', '9').exitstatus).to eq(3)
  end

  it 'never knows pid 0 (dash: 127)' do
    expect(run('0').exitstatus).to eq(127)
  end

  it 'accepts an explicit plus sign like dash' do
    expect(run('+5').exitstatus).to eq(127)
  end

  it 'skips a leading -- like dash' do
    expect(run('--', '99999').exitstatus).to eq(127)
  end

  it 'waits for all jobs when -- is the only argument' do
    expect(run('--')).to be_success
  end

  it 'rejects a non-numeric operand with status 2' do
    expect(run('abc').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("wait: Illegal number: abc\n")
  end

  it 'rejects a value past INT_MAX like a non-numeric one' do
    expect(run('99999999999999').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("wait: Illegal number: 99999999999999\n")
  end

  it 'reads a leading dash as an illegal option' do
    expect(run('-5').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("wait: Illegal option -5\n")
  end

  it 'treats the bare - as a bad number, not an option (dash-verified)' do
    expect(run('-').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("wait: Illegal number: -\n")
  end

  it 'stops at the first malformed operand' do
    launch(9, 3)
    expect(run('abc', '9').exitstatus).to eq(2)
    expect(run('9').exitstatus).to eq(3)
  end

  it 'resolves %n and %% to jobs, without forgetting them' do
    launch(9, 3)
    expect(run('%1').exitstatus).to eq(3)
    expect(run('%%').exitstatus).to eq(3)
  end

  it 'reports No such job for an unknown %id with status 2' do
    launch(9, 3)
    expect(run('%4').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("wait: No such job: %4\n")
  end

  it 'reports No current job for %% when the table is empty' do
    expect(run('%%').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("wait: No current job\n")
  end

  it 'resolves %- to the previous job' do
    launch(9, 3)
    launch(11, 5)
    expect(run('%-').exitstatus).to eq(3)
  end

  it 'reports No previous job for %- with a single job' do
    launch(9, 3)
    expect(run('%-').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("wait: No previous job\n")
  end
end
