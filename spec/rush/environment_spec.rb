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
    expect { env.assign('A', '2') }.to raise_error(Rush::ReadonlyError, /read only/)
  end

  it 'rejects unsetting a read-only variable' do
    env = described_class.new({})
    env.readonly('A')
    expect { env.unset('A') }.to raise_error(Rush::ReadonlyError)
  end

  it 'keeps LINENO dynamic until user code assigns or unsets it' do
    env = described_class.new({})
    env.update_lineno(2)
    env.assign('LINENO', 'fixed')
    env.update_lineno(3)
    expect(env.get('LINENO')).to eq('fixed')

    other = described_class.new({})
    other.update_lineno(4)
    other.unset('LINENO')
    other.update_lineno(5)
    expect(other.get('LINENO')).to be_nil
  end

  it 'does not make an inherited LINENO dynamic' do
    env = described_class.new('LINENO' => '99')
    env.update_lineno(2)
    expect(env.get('LINENO')).to eq('99')
  end
end
