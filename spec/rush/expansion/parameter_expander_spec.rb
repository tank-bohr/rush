# frozen_string_literal: true

RSpec.describe Rush::Expansion::ParameterExpander do
  let(:env) { Rush::Environment.new({}) }
  let(:state) { Rush::ShellState.new(environment: env) }
  let(:executor) { Rush::Executor.new(system: FakeSystemCalls.new, state: state) }

  def expand(name, op: nil, arg: nil, quoted: false)
    ref = Rush::AST::ParamRef.new(name: name, op: op, arg: arg)
    described_class.new(executor, ref, quoted: quoted).expand
  end

  it 'expands a set variable, and an unset one to empty' do
    env.assign('X', 'val')
    expect([expand('X'), expand('Z')]).to eq(['val', ''])
  end

  describe Rush::Expansion::ParameterParts do
    it 'uses the outer quoting context for operator-word tilde expansion' do
      env.assign('HOME', '/home/test')

      bare = described_class.new(executor, false)
      quoted = described_class.new(executor, true)
      expected = [[['/home/test', true, false, false]], [['~', false, false, true]]]
      expect([bare.operator('~'), quoted.operator('~')]).to eq(expected)
      expect([bare.pattern('~'), quoted.pattern('~')]).to eq(['/home/test', '~'])
    end

    it 'collapses break-flagged parts with the current IFS separator' do
      env.assign('IFS', ':')
      parts = [['a', true, false, false], ['b', false, true, true]]

      expect(described_class.new(executor, false).collapse(parts)).to eq('a:b')
    end

    it 'anchors an empty quoted $@ only inside the operator word' do
      parts = described_class.new(executor, false)

      expect(parts.operator('"$@"')).to eq([['', false, false, true]])
      expect(parts.operator('"$@"$@')).to eq([['', false, false, true]])
      expect(parts.operator('$@')).to eq([])
      expect(parts.operator('x"$@"')).to eq([['x', true, false, false]])
      expect(executor.expander.expand([Rush::Lexer::WordScanner.entire('"$@"')])).to eq([])
    end
  end

  describe 'default and alternative forms' do
    it 'uses the default only when unset (- keeps null, :- replaces it)' do
      env.assign('E', '')
      expect(expand('Z', op: ':-', arg: 'd')).to eq('d')
      expect(expand('E', op: '-', arg: 'd')).to eq('')
      expect(expand('E', op: ':-', arg: 'd')).to eq('d')
    end

    it 'returns the alternative only when set' do
      env.assign('B', 'x')
      expect([expand('B', op: ':+', arg: 'alt'), expand('Z', op: ':+', arg: 'alt')]).to eq(['alt', ''])
    end

    it 're-scans the word by its quoting context: single quotes and ~ stay ordinary when quoted' do
      expect(expand('Z', op: ':-', arg: "'d'")).to eq('d')
      expect(expand('Z', op: ':-', arg: "'d'", quoted: true)).to eq("'d'")
      expect(expand('Z', op: ':-', arg: '~', quoted: true)).to eq('~')
    end

    it 'preserves quoted and unquoted regions in a selected operator word' do
      ref = Rush::AST::ParamRef.new(name: 'Z', op: ':-', arg: 'left" x y "right')
      parts = described_class.new(executor, ref, quoted: false).expand_parts

      expect(parts).to eq([
                            ['left', true, false, false],
                            [' x y ', false, false, true],
                            ['right', true, false, false]
                          ])
    end
  end

  describe 'assign form' do
    it 'assigns and returns the default when unset, leaving a set value alone' do
      expect(expand('A', op: ':=', arg: 'set')).to eq('set')
      expect(env.get('A')).to eq('set')
      env.assign('C', 'keep')
      expect(expand('C', op: ':=', arg: 'x')).to eq('keep')
    end

    it 'returns the assigned text with the outer parameter quoting policy' do
      ref = Rush::AST::ParamRef.new(name: 'A', op: ':=', arg: '"x y"')
      expander = described_class.new(executor, ref, quoted: false)

      expect(expander.expand_parts).to eq([['x y', true, false, false]])
      expect(env.get('A')).to eq('x y')
    end
  end

  describe 'error form' do
    it 'raises with the given message when unset' do
      expect { expand('Z', op: ':?', arg: 'boom') }.to raise_error(Rush::ExpansionError, /boom/)
    end

    it 'raises with a default message when no word is given' do
      expect { expand('Z', op: ':?', arg: '') }.to raise_error(Rush::ExpansionError, /null or not set/)
    end

    it 'returns the value when set' do
      env.assign('S', 'ok')
      expect(expand('S', op: ':?', arg: 'boom')).to eq('ok')
    end
  end

  it 'expands the operator word itself' do
    env.assign('Y', 'deep')
    expect(expand('Z', op: ':-', arg: '$Y')).to eq('deep')
  end

  describe 'nounset (set -u)' do
    before { state.options.set(:nounset, true) }

    it 'raises for an unset name or positional' do
      expect { expand('missing') }.to raise_error(Rush::ExpansionError, /not set/)
    end

    it 'allows a set value, a default form and special parameters' do
      env.assign('S', 'v')
      expect([expand('S'), expand('Z', op: ':-', arg: 'd'), expand('@'), expand('!')]).to eq(['v', 'd', '', ''])
    end
  end

  describe 'length and pattern-removal forms' do
    it 'returns the length of the value (zero when unset)' do
      env.assign('X', 'abcdef')
      expect([expand('X', op: '#len'), expand('Z', op: '#len')]).to eq(%w[6 0])
    end

    it 'removes matching prefixes and suffixes, smallest and largest' do
      env.assign('F', 'foo.tar.gz')
      expect([expand('F', op: '#', arg: '*.'), expand('F', op: '##', arg: '*.')]).to eq(['tar.gz', 'gz'])
      expect([expand('F', op: '%', arg: '.*'), expand('F', op: '%%', arg: '.*')]).to eq(['foo.tar', 'foo'])
    end

    it 'preserves an escaped closing bracket inside the pattern' do
      env.assign('X', ']tail')

      expect(expand('X', op: '#', arg: '[[:digit:]\\]]')).to eq('tail')
    end
  end
end
