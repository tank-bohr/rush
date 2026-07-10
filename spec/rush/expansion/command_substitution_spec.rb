# frozen_string_literal: true

RSpec.describe Rush::Expansion::CommandSubstitution do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def status_double(code)
    instance_double(Process::Status, exitstatus: code, termsig: nil, stopped?: false)
  end

  describe '#call (parent side)' do
    it 'reads the child output from the pipe, closes both pipe ends and strips trailing newlines' do
      read = StringIO.new("hello\n\n")
      write = StringIO.new
      allow(system).to receive_messages(pipe: [read, write], fork: 55)
      allow(system).to receive(:waitpid2).with(55).and_return([55, status_double(0)])
      expect(described_class.new(executor, 'echo hello').expand).to eq('hello')
      expect([read.closed?, write.closed?]).to eq([true, true])
    end

    it 'records the child exit status as the command-substitution status' do
      allow(system).to receive_messages(pipe: [StringIO.new, StringIO.new], fork: 7)
      allow(system).to receive(:waitpid2).with(7).and_return([7, status_double(3)])
      described_class.new(executor, 'exit 3').expand
      expect([executor.cmd_sub_status.class, executor.cmd_sub_status.exitstatus]).to eq([Rush::Status, 3])
    end

    it 'passes the pipe writer to the spawned child' do
      read = StringIO.new
      write = StringIO.new
      substitution = described_class.new(executor, 'echo hello')
      allow(system).to receive(:pipe).and_return([read, write])
      allow(substitution).to receive(:spawn_child).with(write).and_return(55)
      allow(system).to receive(:waitpid2).with(55).and_return([55, status_double(0)])
      expect(substitution.expand).to eq('')
      expect(substitution).to have_received(:spawn_child).with(write)
    end
  end

  describe '#capture (child side)' do
    it 'runs the parsed body with stdout bound to the writer' do
      write = StringIO.new
      described_class.new(executor, 'echo captured').capture(write)
      expect(write.string).to eq("captured\n")
    end

    it 'parses the body with the current alias table' do
      state.aliases.define('sayit', 'echo alias-body')
      write = StringIO.new
      described_class.new(executor, 'sayit').capture(write)
      expect(write.string).to eq("alias-body\n")
    end

    it 'ends the substitution on a set -e failure without exiting the parent' do
      state.options.set(:errexit, true)
      write = StringIO.new
      described_class.new(executor, 'false; echo nope').capture(write)
      expect([write.string, state.last_status.exitstatus]).to eq(['', 1])
    end

    it 'runs in a fresh errexit context even when the caller is tested' do
      state.options.set(:errexit, true)
      write = StringIO.new
      executor.tested { described_class.new(executor, 'false; echo nope').capture(write) }
      expect([write.string, state.last_status.exitstatus]).to eq(['', 1])
    end

    it 'ends the substitution with the code when an uncaught return runs' do
      write = StringIO.new
      status = described_class.new(executor, 'return 5; echo nope').capture(write)
      expect([write.string, status.exitstatus, state.last_status.exitstatus]).to eq(['', 5, 5])
    end

    it 'runs an EXIT trap set inside the substitution' do
      write = StringIO.new
      status = described_class.new(executor, "trap 'echo cs-exit' EXIT; :").capture(write)
      expect([write.string, status.exitstatus]).to eq(["cs-exit\n", 0])
    end

    it 'resets inherited caught traps while preserving ignored traps' do
      state.traps.set(Rush::Signals::EXIT, 'echo parent')
      state.traps.set('TERM', 'echo term')
      state.traps.set('INT', '')
      write = StringIO.new
      described_class.new(executor, 'trap').capture(write)
      expect(write.string).to eq("trap -- '' INT\n")
    end

    it 'spawns a child process that runs the child side with the writer' do
      write = StringIO.new
      substitution = described_class.new(executor, 'echo nope')
      allow(system).to receive(:fork).and_yield.and_return(55)
      allow(substitution).to receive(:run_child).with(write)
      expect(substitution.send(:spawn_child, write)).to eq(55)
      expect(substitution).to have_received(:run_child).with(write)
    end

    it 'exits the child with the captured body status' do
      exited = []
      system.define_singleton_method(:exit!) { |code| exited << code }
      write = StringIO.new
      substitution = described_class.new(executor, 'echo child')
      wrong_exit = Class.new(StandardError)
      substitution.define_singleton_method(:exit!) { |_code| raise wrong_exit, 'wrong exit receiver' }
      substitution.send(:run_child, write)
      expect([write.string, exited]).to eq(["child\n", [0]])
    end
  end
end
