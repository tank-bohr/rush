# frozen_string_literal: true

RSpec.describe Rush::Builtins::Return do
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: FakeSystemCalls.new, state: state) }
  let(:io) { Rush::IoTable.standard(FakeSystemCalls.new) }

  it 'raises a ReturnSignal with the given code' do
    expect { described_class.new(executor, %w[return 5], io).call }
      .to raise_error(Rush::ReturnSignal) { |signal| expect(signal.code).to eq(5) }
  end

  it 'defaults to the last command status' do
    state.last_status = Rush::Status.new(7)
    expect { described_class.new(executor, %w[return], io).call }
      .to raise_error(Rush::ReturnSignal) { |signal| expect(signal.code).to eq(7) }
  end

  it 'accepts a signed operand with surrounding blanks' do
    expect { described_class.new(executor, ['return', ' +5 '], io).call }
      .to raise_error(Rush::ReturnSignal) { |signal| expect(signal.code).to eq(5) }
  end

  it 'raises a BuiltinError for a non-numeric operand' do
    expect { described_class.new(executor, %w[return abc], io).call }.to raise_error(Rush::BuiltinError)
  end
end
