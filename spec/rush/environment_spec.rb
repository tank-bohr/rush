# frozen_string_literal: true

RSpec.describe Rush::Environment do
  it 'defaults its source to the process environment' do
    expect(described_class.new.get('PATH')).to eq(ENV.fetch('PATH'))
  end

  it 'reads and writes variables, stringifying values' do
    env = described_class.new({})
    env.assign('N', 5)
    expect(env.get('N')).to eq('5')
  end

  it 'exports only the variables that were marked for export' do
    env = described_class.new({})
    env.assign('A', 'x')
    env.assign('B', 'y')
    env.export('A')
    expect(env.exported).to eq('A' => 'x')
  end

  it 'unsets a variable and drops it from the exported set' do
    env = described_class.new({})
    env.assign('A', 'x')
    env.export('A')
    env.unset('A')
    expect([env.get('A'), env.exported]).to eq([nil, {}])
  end
end
