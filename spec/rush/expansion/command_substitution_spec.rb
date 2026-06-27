# frozen_string_literal: true

RSpec.describe Rush::Expansion::CommandSubstitution do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  describe '#call (parent side)' do
    it 'reads the child output from the pipe and strips trailing newlines' do
      allow(system).to receive_messages(pipe: [StringIO.new("hello\n\n"), StringIO.new], fork: 55)
      allow(system).to receive(:waitpid2).with(55).and_return([55, nil])
      expect(described_class.new(executor, 'echo hello').call).to eq('hello')
    end
  end

  describe '#capture (child side)' do
    it 'runs the parsed body with stdout bound to the writer' do
      write = StringIO.new
      described_class.new(executor, 'echo captured').capture(write)
      expect(write.string).to eq("captured\n")
    end
  end
end
