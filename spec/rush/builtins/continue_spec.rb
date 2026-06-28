# frozen_string_literal: true

RSpec.describe Rush::Builtins::Continue do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['continue', *args], io).call
  end

  context 'when inside a loop' do
    before { state.loops.enter }

    it 'raises a ContinueSignal with the default level of 1' do
      expect { run }.to raise_error(Rush::ContinueSignal) { |signal| expect(signal.count).to eq(1) }
    end

    it 'raises a ContinueSignal with the requested level' do
      state.loops.enter
      state.loops.enter
      expect { run('3') }.to raise_error(Rush::ContinueSignal) { |signal| expect(signal.count).to eq(3) }
    end

    it 'clamps a level past the actual nesting to the loop depth' do
      expect { run('9') }.to raise_error(Rush::ContinueSignal) { |signal| expect(signal.count).to eq(1) }
    end

    it 'sets $? to success before unwinding (continue is a successful builtin)' do
      state.record_status(Rush::Status.new(1))
      expect { run }.to raise_error(Rush::ContinueSignal)
      expect(state.last_status).to be_success
    end
  end

  context 'with no enclosing loop' do
    it 'is a no-op that succeeds without raising' do
      state.record_status(Rush::Status.new(1))
      expect(run).to be_success
      expect(state.last_status).to be_success
    end

    it 'still validates the level operand (a bad one aborts even with no loop)' do
      expect { run('abc') }.to raise_error(Rush::BuiltinError)
      expect { run('0') }.to raise_error(Rush::BuiltinError)
    end
  end
end
