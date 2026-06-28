# frozen_string_literal: true

RSpec.describe Rush::Expansion::Pipeline do
  let(:segment) { Rush::AST::WordSegment }

  describe 'literal expansion' do
    subject(:pipeline) { described_class.new(Rush::Executor.new(system: FakeSystemCalls.new, state: Rush::ShellState.new)) }

    it 'expands each word to one field' do
      words = [Rush::AST::Word.literal('a'), Rush::AST::Word.literal('b')]
      expect(pipeline.expand(words)).to eq(%w[a b])
    end

    it "concatenates a word's segments into a single field" do
      word = Rush::AST::Word.new([segment.new(kind: :literal, value: 'a ', quoted: true),
                                  segment.new(kind: :literal, value: 'b', quoted: false)])
      expect(pipeline.expand([word])).to eq(['a b'])
    end

    it 'expands an assignment value to a single concatenated field' do
      expect(pipeline.expand_value(Rush::AST::Word.literal('v'))).to eq('v')
    end
  end

  it 'parameter-expands a :param segment' do
    state = Rush::ShellState.new(environment: Rush::Environment.new('X' => 'v'))
    executor = Rush::Executor.new(system: FakeSystemCalls.new, state: state)
    ref = Rush::AST::ParamRef.simple('X')
    word = Rush::AST::Word.new([segment.new(kind: :param, value: ref, quoted: false)])
    expect(described_class.new(executor).expand([word])).to eq(['v'])
  end

  it 'runs a command substitution for a :command segment' do
    executor = Rush::Executor.new(system: FakeSystemCalls.new, state: Rush::ShellState.new)
    sub = instance_double(Rush::Expansion::CommandSubstitution, expand: 'OUT')
    allow(Rush::Expansion::CommandSubstitution).to receive(:new).and_return(sub)
    word = Rush::AST::Word.new([segment.new(kind: :command, value: 'echo x', quoted: false)])
    expect(described_class.new(executor).expand([word])).to eq(['OUT'])
  end

  it 'field-splits an unquoted parameter but not a quoted one' do
    state = Rush::ShellState.new(environment: Rush::Environment.new('X' => 'a b'))
    pipeline = described_class.new(Rush::Executor.new(system: FakeSystemCalls.new, state: state))
    ref = Rush::AST::ParamRef.simple('X')
    unquoted = Rush::AST::Word.new([segment.new(kind: :param, value: ref, quoted: false)])
    quoted = Rush::AST::Word.new([segment.new(kind: :param, value: ref, quoted: true)])
    expect([pipeline.expand([unquoted]), pipeline.expand([quoted])]).to eq([%w[a b], ['a b']])
  end

  describe '"$@" splat expansion' do
    subject(:pipeline) { described_class.new(Rush::Executor.new(system: FakeSystemCalls.new, state: state)) }

    let(:state) { Rush::ShellState.new }

    def at(quoted)
      ref = Rush::AST::ParamRef.simple('@')
      [Rush::AST::Word.new([segment.new(kind: :param, value: ref, quoted: quoted)])]
    end

    it 'yields one field per positional parameter when quoted, preserving spaces' do
      state.positional = ['a b', 'c']
      expect(pipeline.expand(at(true))).to eq(['a b', 'c'])
    end

    it 'field-splits each parameter when unquoted' do
      state.positional = ['a b', 'c']
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

    def star(quoted) = [Rush::AST::Word.new([segment.new(kind: :literal, value: '*', quoted: quoted)])]

    it 'globs an unquoted pattern but leaves a quoted one literal' do
      expect([pipeline.expand(star(false)), pipeline.expand(star(true))]).to eq([%w[x y], ['*']])
    end
  end

  describe '$* expansion' do
    let(:state) { Rush::ShellState.new(environment: Rush::Environment.new('IFS' => ':')) }
    let(:pipeline) { described_class.new(Rush::Executor.new(system: FakeSystemCalls.new, state: state)) }

    def star(quoted)
      ref = Rush::AST::ParamRef.simple('*')
      [Rush::AST::Word.new([segment.new(kind: :param, value: ref, quoted: quoted)])]
    end

    it 'keeps each positional parameter a separate field when unquoted' do
      state.positional = ['a b', 'c']
      expect(pipeline.expand(star(false))).to eq(['a b', 'c'])
    end

    it 'joins the positional parameters with the first IFS character when quoted' do
      state.positional = %w[a b c]
      expect(pipeline.expand(star(true))).to eq(['a:b:c'])
    end
  end
end
