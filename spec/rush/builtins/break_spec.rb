# frozen_string_literal: true

RSpec.describe Rush::Builtins::Break do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['break', *args], io).call

  context 'when inside a loop' do
    before { state.enter_loop }

    it 'raises a BreakSignal with the default level of 1' do
      expect { run }.to raise_error(Rush::BreakSignal) { |signal| expect(signal.count).to eq(1) }
    end

    it 'raises a BreakSignal with the requested level' do
      state.enter_loop
      expect { run('2') }.to raise_error(Rush::BreakSignal) { |signal| expect(signal.count).to eq(2) }
    end

    it 'clamps a level past the actual nesting to the loop depth' do
      expect { run('5') }.to raise_error(Rush::BreakSignal) { |signal| expect(signal.count).to eq(1) }
    end

    it 'sets $? to success before unwinding (break is a successful builtin)' do
      state.last_status = Rush::Status.new(1)
      expect { run }.to raise_error(Rush::BreakSignal)
      expect(state.last_status).to be_success
    end
  end

  context 'with no enclosing loop' do
    it 'is a no-op that succeeds without raising' do
      state.last_status = Rush::Status.new(1)
      expect(run).to be_success
      expect(state.last_status).to be_success
    end

    it 'still validates the level operand (a bad one aborts even with no loop)' do
      expect { run('abc') }.to raise_error(Rush::BuiltinError)
      expect { run('0') }.to raise_error(Rush::BuiltinError)
    end
  end
end
