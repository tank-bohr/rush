# frozen_string_literal: true

RSpec.describe Rush::Builtins::Fg do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def fg(*args)
    described_class.new(executor, ['fg', *args], io).call
  end

  before do
    executor.jobs.control.engage(nil)
    executor.jobs.adopt_stopped([50, 51], 20, 'sleep 100 | cat')
  end

  it 'resumes, waits for every member and frees the finished entry, its status as $?' do
    system.provide_child(50, 0)
    system.provide_child(51, 7)
    expect(fg('%1').exitstatus).to eq(7)
    expect(system.kills).to eq([['CONT', -50]])
    expect(executor.jobs.current).to be_nil
  end

  it 'reports a signal death of the resumed job on stderr, like any foreground wait (rush-hkp)' do
    system.provide_signalled(50, 9)
    system.provide_signalled(51, 9)
    expect(fg('%1').exitstatus).to eq(137)
    expect(system.stderr.string).to eq("Killed\n")
  end

  it 'prints the command line to stdout, as dash echoes what it resumes' do
    system.provide_child(50, 0)
    system.provide_child(51, 0)
    fg('%1')
    expect(system.stdout.string).to eq("sleep 100 | cat\n")
  end

  it 'parks the job Stopped again, same number, when the resumed job takes another ^Z' do
    system.provide_stopped(50, 20)
    system.provide_stopped(51, 20)
    expect(fg('%1').exitstatus).to eq(148)
    job = executor.jobs.current
    expect([job.number, job.stopped?, job.text]).to eq([1, true, 'sleep 100 | cat'])
  end

  it 'hands the terminal to the job group for the wait and reclaims it' do
    tty_system = FakeSystemCalls.new(tty: true)
    tty_executor = Rush::Executor.new(system: tty_system, state: state)
    tty_executor.job_control.enable(tty_system.stderr)
    tty_executor.jobs.adopt_stopped([50], 20, 'sleep 9')
    tty_system.provide_child(50, 0)
    described_class.new(tty_executor, %w[fg %1], Rush::IoTable.standard(tty_system)).call
    expect(tty_system.handovers).to eq([4242, 50, 4242])
  end

  it 'answers the remembered status of an already-dead job and frees it (dash-probed 137)' do
    executor.jobs.current.finish(FakeSystemCalls::ChildStatus.new(nil, 9))
    expect(fg('%1').exitstatus).to eq(137)
    expect(executor.jobs.current).to be_nil
    expect(system.kills).to eq([['CONT', -50]])
  end

  it 'keeps a re-stopped entry in the table instead of freeing it' do
    system.provide_stopped(50, 19)
    system.provide_stopped(51, 19)
    fg('%1')
    expect(executor.jobs.current).not_to be_nil
  end

  it 'swallows ESRCH when the group is already gone' do
    dead = FakeSystemCalls.new(dead_pids: [-50])
    dead_executor = Rush::Executor.new(system: dead, state: state)
    dead_executor.jobs.control.engage(nil)
    dead_executor.jobs.adopt_stopped([50], 20, 'sleep 9')
    dead_executor.jobs.current.finish(FakeSystemCalls::ChildStatus.new(nil, 9))
    status = described_class.new(dead_executor, %w[fg %1], Rush::IoTable.standard(dead)).call
    expect(status.exitstatus).to eq(137)
  end
end
