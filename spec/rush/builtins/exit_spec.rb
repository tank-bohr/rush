# frozen_string_literal: true

RSpec.describe Rush::Builtins::Exit do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  it 'exits with the given numeric operand' do
    expect { described_class.new(executor, %w[exit 4], io).call }
      .to raise_error(Rush::ExitSignal) { |signal| expect(signal.code).to eq(4) }
  end

  it 'exits with the last status when no operand is given' do
    state.last_status = Rush::Status.new(7)
    expect { described_class.new(executor, %w[exit], io).call }
      .to raise_error(Rush::ExitSignal) { |signal| expect(signal.code).to eq(7) }
  end

  it 'raises a BuiltinError for a negative or non-numeric operand' do
    expect { described_class.new(executor, %w[exit -1], io).call }.to raise_error(Rush::BuiltinError)
    expect { described_class.new(executor, %w[exit abc], io).call }.to raise_error(Rush::BuiltinError)
  end
end
