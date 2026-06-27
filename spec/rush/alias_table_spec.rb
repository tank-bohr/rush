# frozen_string_literal: true

RSpec.describe Rush::AliasTable do
  subject(:table) { described_class.new }

  it 'stores and reads back a definition' do
    table.define('ll', 'ls -l')
    expect([table.value('ll'), table.key?('ll')]).to eq(['ls -l', true])
  end

  it 'reports an undefined name' do
    expect([table.value('nope'), table.key?('nope')]).to eq([nil, false])
  end

  it 'overwrites a redefinition' do
    table.define('a', '1')
    table.define('a', '2')
    expect(table.value('a')).to eq('2')
  end

  it 'removes a name and returns its old value' do
    table.define('a', '1')
    expect([table.remove('a'), table.key?('a')]).to eq(['1', false])
  end

  it 'returns nil when removing an unknown name' do
    expect(table.remove('gone')).to be_nil
  end

  it 'clears every definition' do
    table.define('a', '1')
    table.define('b', '2')
    table.clear
    expect(table.listing).to eq([])
  end

  it 'lists name/value pairs sorted by name' do
    table.define('zzz', '1')
    table.define('aaa', '2')
    expect(table.listing).to eq([%w[aaa 2], %w[zzz 1]])
  end
end
