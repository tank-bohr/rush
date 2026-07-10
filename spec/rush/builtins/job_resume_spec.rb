# frozen_string_literal: true

RSpec.describe 'fg and bg' do # rubocop:disable RSpec/DescribeClass -- one suite for the JobResume pair
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def fg(*args)
    Rush::Builtins::Fg.new(executor, ['fg', *args], io).call
  end

  def bg(*args)
    Rush::Builtins::Bg.new(executor, ['bg', *args], io).call
  end

  describe 'resolution and the job-control refusal (ported from the phase-5 stubs)' do
    it 'reports No current job when the table is empty' do
      expect(fg.exitstatus).to eq(2)
      expect(system.stderr.string).to eq("fg: No current job\n")
    end

    it 'refuses the current job when it was not created under job control' do
      executor.jobs.record(11)
      expect(fg.exitstatus).to eq(2)
      expect(system.stderr.string).to eq("fg: job not created under job control\n")
    end

    it 'echoes the operand in the refusal, under the invoked name' do
      executor.jobs.record(11)
      expect(bg('%1').exitstatus).to eq(2)
      expect(system.stderr.string).to eq("bg: job %1 not created under job control\n")
    end

    it 'reports No such job for an unresolvable operand' do
      expect(bg('%7').exitstatus).to eq(2)
      expect(system.stderr.string).to eq("bg: No such job: %7\n")
    end

    it 'keeps refusing a plain job even while monitor is on now (dash: the bit is per job)' do
      executor.jobs.record(11)
      executor.job_control.enable(system.stderr)
      expect(fg('%1').exitstatus).to eq(2)
      expect(system.stderr.string).to eq("fg: job %1 not created under job control\n")
    end
  end

  describe 'with a stopped job under job control' do
    before do
      executor.jobs.control.engage(nil)
      executor.jobs.adopt_stopped([50, 51], 20)
    end

    it 'bg resumes the group: SIGCONT to -pgid, entry Running, "[n]" printed, status 0' do
      expect(bg('%1')).to be_success
      expect(system.kills).to eq([['CONT', -50]])
      expect(executor.jobs.current.running?).to be(true)
      expect(system.stdout.string).to eq("[1]\n")
    end

    it 'fg resumes, waits for every member and frees the finished entry, its status as $?' do
      system.provide_child(50, 0)
      system.provide_child(51, 7)
      expect(fg('%1').exitstatus).to eq(7)
      expect(system.kills).to eq([['CONT', -50]])
      expect(executor.jobs.current).to be_nil
    end

    it 'fg prints the command-line placeholder to stdout (text arrives with mv8.6)' do
      system.provide_child(50, 0)
      system.provide_child(51, 0)
      fg('%1')
      expect(system.stdout.string).to eq("\n")
    end

    it 'fg parks the job Stopped again, same number, when the resumed job takes another ^Z' do
      system.provide_stopped(50, 20)
      system.provide_stopped(51, 20)
      expect(fg('%1').exitstatus).to eq(148)
      job = executor.jobs.current
      expect([job.number, job.stopped?]).to eq([1, true])
    end

    it 'fg hands the terminal to the job group for the wait and reclaims it' do
      tty_system = FakeSystemCalls.new(tty: true)
      tty_executor = Rush::Executor.new(system: tty_system, state: state)
      tty_executor.job_control.enable(tty_system.stderr)
      tty_executor.jobs.adopt_stopped([50], 20)
      tty_system.provide_child(50, 0)
      Rush::Builtins::Fg.new(tty_executor, %w[fg %1], Rush::IoTable.standard(tty_system)).call
      expect(tty_system.handovers).to eq([4242, 50, 4242])
    end

    it 'fg answers the remembered status of an already-dead job and frees it (dash-probed 137)' do
      executor.jobs.current.finish(FakeSystemCalls::ChildStatus.new(nil, 9))
      expect(fg('%1').exitstatus).to eq(137)
      expect(executor.jobs.current).to be_nil
    end

    it 'loops multiple operands, the last status winning (dash fg %1 %2)' do
      executor.jobs.adopt_stopped([60], 20)
      system.provide_child(50, 3)
      system.provide_child(51, 3)
      system.provide_child(60, 5)
      expect(fg('%1', '%2').exitstatus).to eq(5)
      expect(system.kills).to eq([['CONT', -50], ['CONT', -60]])
    end

    it 'swallows ESRCH when the group is already gone' do
      dead = FakeSystemCalls.new(dead_pids: [-50])
      dead_executor = Rush::Executor.new(system: dead, state: state)
      dead_executor.jobs.control.engage(nil)
      dead_executor.jobs.adopt_stopped([50], 20)
      dead_executor.jobs.current.finish(FakeSystemCalls::ChildStatus.new(nil, 9))
      status = Rush::Builtins::Fg.new(dead_executor, %w[fg %1], Rush::IoTable.standard(dead)).call
      expect(status.exitstatus).to eq(137)
    end
  end
end
