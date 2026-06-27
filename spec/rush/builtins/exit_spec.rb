# frozen_string_literal: true

RSpec.describe Rush::Builtins::Exit do
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: FakeSystemCalls.new, state: state) }

  it 'exits with the given numeric operand' do
    expect { described_class.new(executor, %w[exit 4]).call }
      .to raise_error(Rush::ExitSignal) { |signal| expect(signal.code).to eq(4) }
  end

  it 'exits with the last status when no operand is given' do
    state.last_status = Rush::Status.new(7)
    expect { described_class.new(executor, %w[exit]).call }
      .to raise_error(Rush::ExitSignal) { |signal| expect(signal.code).to eq(7) }
  end
end
