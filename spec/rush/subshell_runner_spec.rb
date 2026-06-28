# frozen_string_literal: true

RSpec.describe Rush::SubshellRunner do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def body(source) = Rush::Parser.new(Rush::Lexer.new(source)).parse
  def status_double(code) = instance_double(Process::Status, exitstatus: code, termsig: nil)

  describe '#call (parent side)' do
    it 'forks the child, waits for it and adopts its status' do
      allow(system).to receive(:fork).and_return(42)
      allow(system).to receive(:waitpid2).with(42).and_return([42, status_double(3)])
      expect(described_class.new(executor, body('false')).call.exitstatus).to eq(3)
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
