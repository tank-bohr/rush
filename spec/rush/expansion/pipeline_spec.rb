# frozen_string_literal: true

RSpec.describe Rush::Expansion::Pipeline do
  def lit(value, quoted: false)
    Rush::AST::LiteralSegment.new(value, quoted)
  end

  def par(ref, quoted: false)
    Rush::AST::ParamSegment.new(ref, quoted)
  end

  def cmd(source, quoted: false)
    Rush::AST::CommandSegment.new(source, quoted)
  end

  describe 'literal expansion' do
    subject(:pipeline) { described_class.new(Rush::Executor.new(system: FakeSystemCalls.new, state: Rush::ShellState.new)) }

    it 'expands each word to one field' do
      words = [Rush::AST::Word.literal('a'), Rush::AST::Word.literal('b')]
      expect(pipeline.expand(words)).to eq(%w[a b])
    end

    it "concatenates a word's segments into a single field" do
      word = Rush::AST::Word.new([lit('a ', quoted: true), lit('b')])
      expect(pipeline.expand([word])).to eq(['a b'])
    end

    it 'expands an assignment value to a single concatenated field' do
      expect(pipeline.expand_value(Rush::AST::Word.literal('v'))).to eq('v')
    end

    it 'forwards the requested tilde mode while expanding a scalar value' do
      state = Rush::ShellState.new(environment: Rush::Environment.new('HOME' => '/home/test'))
      pipeline = described_class.new(Rush::Executor.new(system: FakeSystemCalls.new, state: state))
      word = Rush::AST::Word.literal('prefix:~')

      expect([pipeline.expand_value(word), pipeline.expand_value(word, tilde: :assignment)])
        .to eq(['prefix:~', 'prefix:/home/test'])
    end

    it 'collapses break boundaries with the current first IFS character' do
      state = Rush::ShellState.new(environment: Rush::Environment.new({}))
      pipeline = described_class.new(Rush::Executor.new(system: FakeSystemCalls.new, state: state))
      parts = [['a', true, false, false], ['b', false, true, true]]

      expect(pipeline.collapse(parts)).to eq('a b')
      state.variables.assign('IFS', ':')
      expect(pipeline.collapse(parts)).to eq('a:b')
      state.variables.assign('IFS', '')
      expect(pipeline.collapse(parts)).to eq('ab')
    end

    it 'backslash-shields only quoted metacharacters in a shell pattern' do
      word = Rush::AST::Word.new([lit('*'), lit('a'), lit(']*?-!^[', quoted: true)])

      expect(pipeline.expand_pattern(word)).to eq('*a\\]\\*\\?\\-\\!\\^\\[')
    end

    it 'expands dynamic segments in a shell pattern with the executor' do
      state = Rush::ShellState.new(environment: Rush::Environment.new('X' => '*'))
      pipeline = described_class.new(Rush::Executor.new(system: FakeSystemCalls.new, state: state))
      word = Rush::AST::Word.new([par(Rush::AST::ParamRef.simple('X'))])

      expect(pipeline.expand_pattern(word)).to eq('*')
    end
  end

  it 'parameter-expands a :param segment' do
    state = Rush::ShellState.new(environment: Rush::Environment.new('X' => 'v'))
    executor = Rush::Executor.new(system: FakeSystemCalls.new, state: state)
    word = Rush::AST::Word.new([par(Rush::AST::ParamRef.simple('X'))])
    expect(described_class.new(executor).expand([word])).to eq(['v'])
  end

  it 'runs a command substitution for a :command segment' do
    executor = Rush::Executor.new(system: FakeSystemCalls.new, state: Rush::ShellState.new)
    sub = instance_double(Rush::Expansion::CommandSubstitution, expand: 'OUT')
    allow(Rush::Expansion::CommandSubstitution).to receive(:new).and_return(sub)
    word = Rush::AST::Word.new([cmd('echo x')])
    expect(described_class.new(executor).expand([word])).to eq(['OUT'])
  end

  it 'field-splits an unquoted parameter but not a quoted one' do
    state = Rush::ShellState.new(environment: Rush::Environment.new('X' => 'a b'))
    pipeline = described_class.new(Rush::Executor.new(system: FakeSystemCalls.new, state: state))
    ref = Rush::AST::ParamRef.simple('X')
    unquoted = Rush::AST::Word.new([par(ref)])
    quoted = Rush::AST::Word.new([par(ref, quoted: true)])
    expect([pipeline.expand([unquoted]), pipeline.expand([quoted])]).to eq([%w[a b], ['a b']])
  end

  it 'keeps quoted regions of an unquoted parameter operator word together' do
    pipeline = described_class.new(Rush::Executor.new(system: FakeSystemCalls.new, state: Rush::ShellState.new))
    ref = Rush::AST::ParamRef.new(name: 'X', op: ':-', arg: 'left" x y "right')

    expect(pipeline.expand([Rush::AST::Word.new([par(ref)])])).to eq(['left x y right'])
  end

  it 'shields a quoted glob inside an unquoted parameter operator word' do
    system = FakeSystemCalls.new(globs: { '*' => %w[file1 file2] })
    pipeline = described_class.new(Rush::Executor.new(system: system, state: Rush::ShellState.new))
    ref = Rush::AST::ParamRef.new(name: 'X', op: ':-', arg: '"*"')

    expect(pipeline.expand([Rush::AST::Word.new([par(ref)])])).to eq(['*'])
  end

  describe '"$@" splat expansion' do
    subject(:pipeline) { described_class.new(Rush::Executor.new(system: FakeSystemCalls.new, state: state)) }

    let(:state) { Rush::ShellState.new }

    def at(quoted)
      [Rush::AST::Word.new([par(Rush::AST::ParamRef.simple('@'), quoted: quoted)])]
    end

    it 'yields one field per positional parameter when quoted, preserving spaces' do
      state.positional.replace(['a b', 'c'])
      expect(pipeline.expand(at(true))).to eq(['a b', 'c'])
      expect(pipeline.expand_parts(at(true).first)).to eq([
                                                            ['a b', false, false, true],
                                                            ['c', false, true, true]
                                                          ])
    end

    it 'field-splits each parameter when unquoted' do
      state.positional.replace(['a b', 'c'])
      expect(pipeline.expand(at(false))).to eq(%w[a b c])
    end

    it 'yields no fields when there are no positional parameters' do
      expect(pipeline.expand(at(true))).to eq([])
    end
  end

  describe 'pathname expansion' do
    let(:state) { Rush::ShellState.new }
    let(:system) { FakeSystemCalls.new(globs: { '*' => %w[x y] }) }
    let(:pipeline) { described_class.new(Rush::Executor.new(system: system, state: state)) }

    def star(quoted)
      [Rush::AST::Word.new([lit('*', quoted: quoted)])]
    end

    it 'globs an unquoted pattern but leaves a quoted one literal' do
      expect([pipeline.expand(star(false)), pipeline.expand(star(true))]).to eq([%w[x y], ['*']])
    end
  end

  describe '$* expansion' do
    let(:state) { Rush::ShellState.new(environment: Rush::Environment.new('IFS' => ':')) }
    let(:pipeline) { described_class.new(Rush::Executor.new(system: FakeSystemCalls.new, state: state)) }

    def star(quoted)
      [Rush::AST::Word.new([par(Rush::AST::ParamRef.simple('*'), quoted: quoted)])]
    end

    it 'keeps each positional parameter a separate field when unquoted' do
      state.positional.replace(['a b', 'c'])
      expect(pipeline.expand(star(false))).to eq(['a b', 'c'])
    end

    it 'joins the positional parameters with the first IFS character when quoted' do
      state.positional.replace(%w[a b c])
      expect(pipeline.expand(star(true))).to eq(['a:b:c'])
    end
  end
end
