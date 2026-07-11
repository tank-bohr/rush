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

  it 'scopes temporary exported values while preserving unrelated builtin writes' do
    env = described_class.new('A' => 'old')
    env.with_temporary('A' => 'temp', 'C' => 'new') do
      expect([env.get('A'), env.get('C'), env.exported]).to eq(['temp', 'new', { 'A' => 'temp', 'C' => 'new' }])
      env.unset('A')
      env.assign('A', 'changed')
      env.readonly('C')
      env.assign('D', 'live')
    end

    expect(env.get('C')).to be_nil
    env.assign('C', 'after')
    expect([env.get('A'), env.get('C'), env.get('D'), env.exported]).to eq(['old', 'after', 'live', { 'A' => 'old' }])
  end

  it 'restores temporary values and LINENO policy when the builtin raises' do
    env = described_class.new({})
    action = -> { env.with_temporary('LINENO' => 'fixed') { raise StandardError, 'boom' } }
    expect(&action).to raise_error(StandardError, 'boom')
    env.update_lineno(9)
    expect(env.get('LINENO')).to eq('9')
  end

  it 'keeps an unrelated builtin change to LINENO policy' do
    env = described_class.new({})
    env.update_lineno(2)
    env.with_temporary('A' => 'temp') { env.unset('LINENO') }
    env.update_lineno(3)
    expect(env.get('LINENO')).to be_nil
  end

  it 'restores readonly state when applying the temporary value fails' do
    env = described_class.new('A' => 'old')
    env.readonly('A')

    expect { env.with_temporary('A' => 'new') { flunk 'unreachable' } }.to raise_error(Rush::ReadonlyError)
    expect([env.get('A'), env.exported]).to eq(['old', { 'A' => 'old' }])
    expect { env.assign('A', 'again') }.to raise_error(Rush::ReadonlyError)
  end
end
