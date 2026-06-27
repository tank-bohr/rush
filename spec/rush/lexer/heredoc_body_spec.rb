# frozen_string_literal: true

RSpec.describe Rush::Lexer::HeredocBody do
  def scan(text) = described_class.new(text).scan
  def kinds(text) = scan(text).segments.map(&:kind)

  it 'keeps plain text as a single literal segment' do
    expect(scan('plain text').literal_text).to eq('plain text')
  end

  it 'parses $name and ${name} into param segments' do
    expect(kinds('a $x b ${y} c')).to eq(%i[literal param literal param literal])
  end

  it 'parses $(...) and `...` into command segments' do
    expect(kinds('$(echo hi) and `date`')).to eq(%i[command literal command])
  end

  it 'keeps an escaped dollar literal rather than a parameter' do
    expect(kinds('\\$x')).to eq([:literal])
    expect(scan('\\$x').literal_text).to eq('$x')
  end

  it 'keeps a backslash before an ordinary character' do
    expect(scan('a\\zb').literal_text).to eq('a\\zb')
  end

  it 'treats a lone $ that starts no name as literal' do
    expect(scan('cost $ 5').literal_text).to eq('cost $ 5')
  end

  it 'raises on an unterminated ${' do
    expect { scan('${x') }.to raise_error(Rush::ParseError, /unterminated/)
  end
end
