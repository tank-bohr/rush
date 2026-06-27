# frozen_string_literal: true

RSpec.describe Rush::Expansion::Pipeline do
  it 'expands each word to its literal text, one field per word' do
    pipeline = described_class.new(:executor)
    words = [Rush::AST::Word.literal('a'), Rush::AST::Word.literal('b')]
    expect(pipeline.expand(words)).to eq(%w[a b])
  end
end
