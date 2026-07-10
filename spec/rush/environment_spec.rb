# frozen_string_literal: true

RSpec.describe Rush::Environment do
  it 'defaults its source to the process environment' do
    expect(described_class.new.get('PATH')).to eq(ENV.fetch('PATH'))
  end

  it 'reads and writes string variables' do
    env = described_class.new({})
    env.assign('N', '5')
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

  it 'rejects assigning to a read-only variable' do
    env = described_class.new({})
    env.assign('A', '1')
    env.readonly('A')
    expect { env.assign('A', '2') }.to raise_error(Rush::ReadonlyError, 'A: is read only')
  end

  it 'rejects unsetting a read-only variable' do
    env = described_class.new({})
    env.readonly('A')
    expect { env.unset('A') }.to raise_error(Rush::ReadonlyError, 'A: is read only')
  end

  it 'copies its source rather than aliasing it' do
    source = { 'A' => '1' }
    env = described_class.new(source)
    env.assign('B', '2')
    env.unset('A')
    expect(source).to eq('A' => '1')
  end

  it 'marks every inherited variable as exported' do
    env = described_class.new('A' => '1', 'B' => '2')
    expect(env.exported).to eq('A' => '1', 'B' => '2')
  end

  it 'unsets only the named variable, leaving other exports alone' do
    env = described_class.new({})
    env.assign('A', 'x')
    env.assign('B', 'y')
    env.export('B')
    env.unset('A')
    expect([env.get('B'), env.exported]).to eq(['y', { 'B' => 'y' }])
  end

  it 'tracks LINENO dynamically while no user code has touched it' do
    env = described_class.new({})
    env.update_lineno(2)
    expect(env.get('LINENO')).to eq('2')
    env.update_lineno(7)
    expect(env.get('LINENO')).to eq('7')
  end

  it 'keeps LINENO dynamic until user code assigns or unsets it' do
    # .dup: the shell sees user-typed names, never this file's frozen literal
    # (a deduplicated literal would let an identity check pass by accident)
    env = described_class.new({})
    env.update_lineno(2)
    env.assign('LINENO'.dup, 'fixed')
    env.update_lineno(3)
    expect(env.get('LINENO')).to eq('fixed')

    other = described_class.new({})
    other.update_lineno(4)
    other.unset('LINENO'.dup)
    other.update_lineno(5)
    expect(other.get('LINENO')).to be_nil
  end

  it 'keeps LINENO dynamic across assignments and unsets of other variables' do
    env = described_class.new({})
    env.assign('A', '1')
    env.unset('A')
    env.update_lineno(6)
    expect(env.get('LINENO')).to eq('6')
  end

  it 'forgets the export mark on unset: a reassignment stays private' do
    env = described_class.new({})
    env.assign('A', 'x')
    env.export('A')
    env.unset('A')
    env.assign('A', 'z')
    expect(env.exported).to eq({})
  end

  it 'does not make an inherited LINENO dynamic' do
    env = described_class.new('LINENO' => '99')
    env.update_lineno(2)
    expect(env.get('LINENO')).to eq('99')
  end
end
