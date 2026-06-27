# frozen_string_literal: true

RSpec.describe Rush::Signals do
  it 'decodes a numeric spec through the signal table' do
    expect(described_class.decode('2')).to eq('INT')
  end

  it 'decodes 0 as the EXIT pseudo-signal' do
    expect(described_class.decode('0')).to eq('EXIT')
  end

  it 'decodes names case-insensitively without a SIG prefix' do
    expect([described_class.decode('int'), described_class.decode('Term')]).to eq(%w[INT TERM])
  end

  it 'rejects a SIG-prefixed name' do
    expect(described_class.decode('SIGINT')).to be_nil
  end

  it 'rejects an out-of-range number' do
    expect(described_class.decode('99')).to be_nil
  end

  it 'rejects an unknown name' do
    expect(described_class.decode('NOPE')).to be_nil
  end

  it 'maps a canonical name back to its signal number' do
    expect(described_class.number('TERM')).to eq(15)
  end
end
