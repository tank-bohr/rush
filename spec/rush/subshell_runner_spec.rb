# frozen_string_literal: true

RSpec.describe Rush::SubshellRunner do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def body(source)
    Rush::Parser.new(Rush::Lexer.new(source)).parse
  end

  def status_double(code)
    instance_double(Process::Status, exitstatus: code, termsig: nil)
  end

  describe '#call (parent side)' do
    it 'forks the child, waits for it and adopts its status' do
      allow(system).to receive(:fork).and_return(42)
      allow(system).to receive(:waitpid2).with(42).and_return([42, status_double(3)])
      expect(described_class.new(executor, body('false')).call.exitstatus).to eq(3)
    end

    it 'places the subshell in its own process group under job control (dash-probed)' do
      executor.job_control.enable(system.stderr)
      allow(system).to receive(:fork).and_return(42)
      allow(system).to receive(:waitpid2).with(42).and_return([42, status_double(0)])
      described_class.new(executor, body('true')).call
      expect(system.pgids_set).to eq([[42, 0]])
    end

    it 'hands the terminal to the subshell for the wait and reclaims after (tty job control)' do
      tty_system = FakeSystemCalls.new(tty: true)
      tty_executor = Rush::Executor.new(system: tty_system, state: state)
      tty_executor.job_control.enable(tty_system.stderr)
      allow(tty_system).to receive(:fork).and_return(42)
      allow(tty_system).to receive(:waitpid2).with(42).and_return([42, status_double(0)])
      described_class.new(tty_executor, body('true')).call
      expect(tty_system.tty_leaders).to eq([42])
      expect(tty_system.handovers).to eq([4242, 42, 4242])
    end
  end

  describe '#run_body (child side)' do
    it 'runs the body in the current executor' do
      described_class.new(executor, body('echo sub')).run_body
      expect(system.stdout.string).to eq("sub\n")
    end

    it 'returns the body status' do
      expect(described_class.new(executor, body('false')).run_body.exitstatus).to eq(1)
    end

    it 'ends with exit code when the body calls exit' do
      expect(described_class.new(executor, body('exit 3')).run_body.exitstatus).to eq(3)
    end

    it 'runs an EXIT trap set inside the subshell and lets it override the status' do
      result = described_class.new(executor, body("trap 'exit 7' EXIT; exit 3")).run_body
      expect(result.exitstatus).to eq(7)
    end

    it 'resets inherited caught traps while preserving ignored traps' do
      state.traps.set(Rush::Signals::EXIT, 'echo parent')
      state.traps.set('TERM', 'echo term')
      state.traps.set('INT', '')
      described_class.new(executor, body('trap')).run_body
      expect(system.stdout.string).to eq("trap -- '' INT\n")
    end

    it 'treats a stray break or continue (no enclosing loop) as a no-op' do
      expect(described_class.new(executor, body('break')).run_body).to be_a(Rush::Status)
      expect(described_class.new(executor, body('continue')).run_body).to be_a(Rush::Status)
    end

    it 'ends the subshell when a break targets a loop in the enclosing parent' do
      state.loops.enter # the subshell is lexically inside a parent loop
      result = described_class.new(executor, body("break\necho unreached")).run_body
      expect([result.exitstatus, system.stdout.string]).to eq([0, ''])
    end

    it 'ends the subshell with the code when an uncaught return runs' do
      expect(described_class.new(executor, body('return 2')).run_body.exitstatus).to eq(2)
    end

    it 'aborts the subshell on a fatal error without letting it escape the fork' do
      result = described_class.new(executor, body('echo ${X:?bad}')).run_body
      expect(result.exitstatus).to eq(2)
      expect(system.stderr.string).to include('bad')
    end
  end
end
