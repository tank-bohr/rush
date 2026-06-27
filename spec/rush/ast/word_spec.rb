# frozen_string_literal: true

RSpec.describe Rush::AST::Word do
  it 'builds a single-literal word from text' do
    expect(described_class.literal('foo').literal_text).to eq('foo')
  end

  it 'concatenates the text of all its segments' do
    segment = Rush::AST::WordSegment
    word = described_class.new([segment.new(kind: :literal, text: 'a'), segment.new(kind: :literal, text: 'b')])
    expect(word.literal_text).to eq('ab')
  end
end
