# frozen_string_literal: true

RSpec.describe Rush::Expansion::Pipeline do
  let(:segment) { Rush::AST::WordSegment }

  describe 'literal expansion (no executor needed)' do
    subject(:pipeline) { described_class.new(:executor) }

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
end
