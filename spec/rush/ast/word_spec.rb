# frozen_string_literal: true

RSpec.describe Rush::AST::Word do
  def lit(value, quoted)
    Rush::AST::LiteralSegment.new(value, quoted)
  end

  it 'builds a single unquoted literal word from text' do
    word = described_class.literal('foo')
    expect(word.literal_text).to eq('foo')
    expect(word.literal_name).to eq('foo')
  end

  it 'concatenates the values of all its segments' do
    word = described_class.new([lit('a', false), lit('b', true)])
    expect(word.literal_text).to eq('ab')
  end

  it 'uses only a single unquoted literal segment as a literal name' do
    expect(described_class.new([lit('a', false), lit('b', false)]).literal_name).to be_nil
    expect(described_class.new([lit('a', true)]).literal_name).to be_nil
  end

  it 'returns the first segment literal value' do
    word = described_class.new([lit('first', false), lit('second', false)])
    expect(word.first_literal_value).to eq('first')
  end

  it 'returns nil when the first segment is not an unquoted literal' do
    word = described_class.new([lit('first', true), lit('second', false)])
    expect(word.first_literal_value).to be_nil
  end
end
