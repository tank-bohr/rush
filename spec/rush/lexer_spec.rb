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
    expect(symbols("a b;c\nd")).to eq([:WORD, :WORD, ';', :WORD, :NEWLINE, :WORD])
  end

  it 'skips a comment to the end of the line' do
    expect(symbols('echo hi # trailing comment')).to eq(%i[WORD WORD])
  end

  it 'tokenizes operators with maximal munch' do
    expect(symbols('a&&b||c|d')).to eq([:WORD, :AND_IF, :WORD, :OR_IF, :WORD, '|', :WORD])
  end

  it 'emits redirection operators and an IO_NUMBER before them' do
    expect(symbols('cat 2>f >>g')).to eq([:WORD, :IO_NUMBER, '>', :WORD, :DGREAT, :WORD])
  end

  it 'recognizes an assignment word in command-prefix position' do
    symbol, value = described_class.new('X=1').next_token
    expect(symbol).to eq(:ASSIGNMENT_WORD)
    expect([value.name, value.value.literal_text]).to eq(%w[X 1])
  end

  it 'treats name=value after the command word as a plain WORD' do
    expect(symbols('echo X=1')).to eq(%i[WORD WORD])
  end

  it 'keeps quoted segments in an assignment value' do
    symbol, value = described_class.new('x="a b"').next_token
    expect(symbol).to eq(:ASSIGNMENT_WORD)
    expect(value.value.literal_text).to eq('a b')
  end

  it 'does not treat a quoted name as an assignment' do
    expect(symbols('"x"=1')).to eq([:WORD])
  end

  it 'recognizes reserved words only in command position' do
    expect(symbols('if x; then y; fi')).to eq([:If, :WORD, ';', :Then, :WORD, ';', :Fi])
  end

  it 'treats a reserved word as a plain WORD in argument position' do
    expect(symbols('echo if then')).to eq(%i[WORD WORD WORD])
  end

  it 'does not treat a quoted reserved word as reserved' do
    expect(symbols("'if'")).to eq([:WORD])
  end

  it 'does not treat a redirection target as a reserved word' do
    expect(symbols('echo > if')).to eq([:WORD, '>', :WORD])
  end

  it 'recognizes brace-group tokens and the bang' do
    expect(symbols('! { echo; }')).to eq([:Bang, :Lbrace, :WORD, ';', :Rbrace])
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
