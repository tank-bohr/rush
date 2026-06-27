# frozen_string_literal: true

RSpec.describe Rush::Builtins::Continue do
  let(:io) { Rush::IoTable.standard(FakeSystemCalls.new) }

  it 'raises a ContinueSignal with the default level of 1' do
    expect { described_class.new(nil, ['continue'], io).call }
      .to raise_error(Rush::ContinueSignal) { |signal| expect(signal.count).to eq(1) }
  end

  it 'raises a ContinueSignal with the requested level' do
    expect { described_class.new(nil, %w[continue 3], io).call }
      .to raise_error(Rush::ContinueSignal) { |signal| expect(signal.count).to eq(3) }
  end
end
