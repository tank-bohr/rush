# frozen_string_literal: true

RSpec.describe Rush::AST::Word do
  let(:segment) { Rush::AST::WordSegment }

  it 'builds a single-literal word from text' do
    expect(described_class.literal('foo').literal_text).to eq('foo')
  end

  it 'concatenates the values of all its segments' do
    word = described_class.new([segment.new(kind: :literal, value: 'a', quoted: false),
                                segment.new(kind: :literal, value: 'b', quoted: true)])
    expect(word.literal_text).to eq('ab')
  end
end
