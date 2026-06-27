# frozen_string_literal: true

RSpec.describe Rush::Lexer do
  def symbols(source)
    lexer = described_class.new(source)
    result = []
    loop do
      token = lexer.next_token
      break if token == [false, false]

      result << token.first
    end
    result
  end

  it 'emits a WORD token carrying a literal word' do
    symbol, word = described_class.new('echo').next_token
    expect(symbol).to eq(:WORD)
    expect(word.literal_text).to eq('echo')
  end

  it 'separates words, semicolons and newlines while skipping blanks' do
    expect(symbols("a b;c\n")).to eq(%i[WORD WORD] + [';'] + %i[WORD NEWLINE])
  end

  it 'skips a comment to the end of the line' do
    expect(symbols("a # comment\nb")).to eq(%i[WORD NEWLINE WORD])
  end

  it 'signals end of input with [false, false]' do
    expect(described_class.new('').next_token).to eq([false, false])
  end

  it 'reports the scanner position as its location' do
    lexer = described_class.new('ab cd')
    lexer.next_token
    expect(lexer.location).to be >= 2
  end
end
