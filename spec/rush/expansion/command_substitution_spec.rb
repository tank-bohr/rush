# frozen_string_literal: true

RSpec.describe Rush::Expansion::CommandSubstitution do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def status_double(code) = instance_double(Process::Status, exitstatus: code, termsig: nil)

  describe '#call (parent side)' do
    it 'reads the child output from the pipe and strips trailing newlines' do
      allow(system).to receive_messages(pipe: [StringIO.new("hello\n\n"), StringIO.new], fork: 55)
      allow(system).to receive(:waitpid2).with(55).and_return([55, status_double(0)])
      expect(described_class.new(executor, 'echo hello').expand).to eq('hello')
    end

    it 'records the child exit status as the command-substitution status' do
      allow(system).to receive_messages(pipe: [StringIO.new, StringIO.new], fork: 7)
      allow(system).to receive(:waitpid2).with(7).and_return([7, status_double(3)])
      described_class.new(executor, 'exit 3').expand
      expect(executor.cmd_sub_status.exitstatus).to eq(3)
    end
  end

  describe '#capture (child side)' do
    it 'runs the parsed body with stdout bound to the writer' do
      write = StringIO.new
      described_class.new(executor, 'echo captured').capture(write)
      expect(write.string).to eq("captured\n")
    end

    it 'ends the substitution on a set -e failure without exiting the parent' do
      state.options.set(:errexit, true)
      write = StringIO.new
      described_class.new(executor, 'false; echo nope').capture(write)
      expect([write.string, state.last_status.exitstatus]).to eq(['', 1])
    end

    it 'ends the substitution with the code when an uncaught return runs' do
      write = StringIO.new
      described_class.new(executor, 'return 5; echo nope').capture(write)
      expect([write.string, state.last_status.exitstatus]).to eq(['', 5])
    end
  end
end
