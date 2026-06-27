# frozen_string_literal: true

RSpec.describe Rush::Builtins::Registry do
  subject(:registry) { described_class.new }

  it 'registers, fetches and reports membership' do
    registry.register('x', Integer)
    expect(registry.fetch('x')).to eq(Integer)
    expect(registry.key?('x')).to be(true)
    expect(registry.key?('y')).to be(false)
    expect(registry.fetch('y')).to be_nil
  end
end
