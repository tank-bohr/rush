# frozen_string_literal: true

RSpec.describe Rush::Expansion::PatternRemoval do
  let(:system) { FakeSystemCalls.new }

  def strip(op, value, pattern)
    described_class.new(system, op, value, pattern).call
  end

  it 'removes the smallest and largest matching prefix' do
    expect(strip('#', 'foo.tar.gz', '*.')).to eq('tar.gz')
    expect(strip('##', 'foo.tar.gz', '*.')).to eq('gz')
  end

  it 'removes the smallest and largest matching suffix' do
    expect(strip('%', 'foo.tar.gz', '.*')).to eq('foo.tar')
    expect(strip('%%', 'foo.tar.gz', '.*')).to eq('foo')
  end

  it 'leaves the value unchanged when no prefix or suffix matches' do
    expect(strip('#', 'abc', 'xyz')).to eq('abc')
    expect(strip('%', 'abc', 'xyz')).to eq('abc')
  end
end
