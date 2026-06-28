# frozen_string_literal: true

RSpec.describe Rush::Builtins::Base do
  let(:io) { Rush::IoTable.standard(FakeSystemCalls.new) }

  it 'raises until a subclass implements #call' do
    expect { described_class.new(nil, [], io).call }.to raise_error(NotImplementedError)
  end

  it 'exposes operands and status helpers to subclasses' do
    subclass = Class.new(described_class) do
      def call
        [operands, success.exitstatus, failure(2).exitstatus]
      end
    end
    expect(subclass.new(nil, %w[name a b], io).call).to eq([%w[a b], 0, 2])
  end
end
