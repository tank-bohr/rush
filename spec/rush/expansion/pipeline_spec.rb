# frozen_string_literal: true

RSpec.describe Rush::Expansion::Pipeline do
  let(:pipeline) { described_class.new(:executor) }
  let(:segment) { Rush::AST::WordSegment }

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
