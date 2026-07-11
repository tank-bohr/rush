# frozen_string_literal: true

RSpec.describe Rush::Builtins::JobResume do
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

    it 'refuses before touching later operands (dash sh_error aborts the loop)' do
      executor.jobs.control.engage(nil)
      executor.jobs.adopt_stopped([50], 20, 'sleep 9')
      executor.jobs.record(60)
      system.provide_child(50, 0)
      expect(bg('%2', '%1').exitstatus).to eq(2)
      expect(system.kills).to be_empty
      expect(system.stderr.string).to eq("bg: job %2 not created under job control\n")
    end

    it 'loops multiple operands, the last status winning (dash fg %1 %2)' do
      executor.jobs.control.engage(nil)
      executor.jobs.adopt_stopped([50], 20, 'sleep 50')
      executor.jobs.adopt_stopped([60], 20, 'sleep 60')
      system.provide_child(50, 3)
      system.provide_child(60, 5)
      expect(fg('%1', '%2').exitstatus).to eq(5)
      expect(system.kills).to eq([['CONT', -50], ['CONT', -60]])
    end

    it 'resumes the current job when no operand is given' do
      executor.jobs.control.engage(nil)
      executor.jobs.adopt_stopped([50], 20, 'sleep 9')
      system.provide_child(50, 4)
      expect(fg.exitstatus).to eq(4)
    end
  end
end
