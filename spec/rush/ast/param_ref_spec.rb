# frozen_string_literal: true

RSpec.describe Rush::AST::ParamRef do
  it 'builds a simple reference with no operator' do
    ref = described_class.simple('x')
    expect([ref.name, ref.op, ref.arg]).to eq(['x', nil, nil])
  end

  it 'parses a plain braced name' do
    ref = described_class.parse('name')
    expect([ref.name, ref.op]).to eq(['name', nil])
  end

  it 'rejects an empty braced reference' do
    expect { described_class.parse('') }.to raise_error(Rush::ExpansionError, 'bad substitution')
  end

  it 'rejects an internal match without a captured name' do
    match = instance_double(MatchData)
    allow(match).to receive(:[]).with(1).and_return(nil)

    expect { described_class.__send__(:braced_name, match) }.to raise_error(Rush::ExpansionError, 'bad substitution')
  end

  it 'parses an operator and its word' do
    ref = described_class.parse('x:-default')
    expect([ref.name, ref.op, ref.arg]).to eq(['x', ':-', 'default'])
  end

  it 'parses a special parameter name' do
    expect(described_class.parse('@').name).to eq('@')
  end

  it 'parses the ${#name} length form' do
    ref = described_class.parse('#name')
    expect([ref.name, ref.op, ref.arg]).to eq(['name', '#len', nil])
  end

  it 'parses a one-character ${#x} length form' do
    ref = described_class.parse('#x')
    expect([ref.name, ref.op, ref.arg]).to eq(['x', '#len', nil])
  end

  it 'keeps ${#} as the count parameter, not a length' do
    ref = described_class.parse('#')
    expect([ref.name, ref.op]).to eq(['#', nil])
  end

  it 'parses a removal operator with its pattern' do
    ref = described_class.parse('f##*.')
    expect([ref.name, ref.op, ref.arg]).to eq(['f', '##', '*.'])
  end

  it 'distinguishes single and double removal operators' do
    expect([described_class.parse('f#p').op, described_class.parse('f%p').op]).to eq(['#', '%'])
    expect([described_class.parse('f##p').op, described_class.parse('f%%p').op]).to eq(['##', '%%'])
  end

  describe '#canon (the dash cmdtxt spelling)' do
    it 'braces a simple name and a special parameter' do
      expect(described_class.simple('T').canon).to eq('${T}')
      expect(described_class.simple('@').canon).to eq('${@}')
    end

    it 'keeps an op and its raw argument as written' do
      expect(described_class.parse('T:-a b').canon).to eq('${T:-a b}')
      expect(described_class.parse('x##*/').canon).to eq('${x##*/}')
    end

    it 'spells the length form as ${#name}' do
      expect(described_class.parse('#T').canon).to eq('${#T}')
    end
  end
end
