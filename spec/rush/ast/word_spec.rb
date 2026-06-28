# frozen_string_literal: true

RSpec.describe Rush::AST::Word do
  def lit(value, quoted)
    Rush::AST::LiteralSegment.new(value, quoted)
  end

  it 'builds a single-literal word from text' do
    expect(described_class.literal('foo').literal_text).to eq('foo')
  end

  it 'concatenates the values of all its segments' do
    word = described_class.new([lit('a', false), lit('b', true)])
    expect(word.literal_text).to eq('ab')
  end
end
