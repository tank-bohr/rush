# frozen_string_literal: true

RSpec.describe Rush::HereDoc do
  subject(:heredoc) do
    described_class.new(delimiter: 'EOF', quoted: true, strip: false, source_line: 4)
  end

  it 'captures the delimiter metadata from the lexer token' do
    expect([heredoc.delimiter, heredoc.quoted, heredoc.strip, heredoc.source_line])
      .to eq(['EOF', true, false, 4])
  end

  it 'defaults the source line to 1' do
    expect(described_class.new(delimiter: 'X', quoted: false, strip: true).source_line).to eq(1)
  end

  it 'starts with an empty body word on its own source line' do
    expect(heredoc.segments).to eq([])
    expect(heredoc.body.source_line).to eq(4)
  end

  it 'quacks like the filled word once the lexer hands the body over' do
    word = Rush::AST::Word.new([Rush::AST::WordSegment.new('line', false)], source_line: 4)
    heredoc.fill(word)

    expect(heredoc.body).to be(word)
    expect(heredoc.segments).to eq(word.segments)
  end
end
