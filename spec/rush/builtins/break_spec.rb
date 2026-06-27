# frozen_string_literal: true

RSpec.describe Rush::Builtins::Break do
  let(:io) { Rush::IoTable.standard(FakeSystemCalls.new) }

  it 'raises a BreakSignal with the default level of 1' do
    expect { described_class.new(nil, ['break'], io).call }
      .to raise_error(Rush::BreakSignal) { |signal| expect(signal.count).to eq(1) }
  end

  it 'raises a BreakSignal with the requested level' do
    expect { described_class.new(nil, %w[break 2], io).call }
      .to raise_error(Rush::BreakSignal) { |signal| expect(signal.count).to eq(2) }
  end
end
