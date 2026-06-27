# frozen_string_literal: true

RSpec.describe Rush::Lexer::SubstitutionReader do
  def reader(source) = described_class.new(StringScanner.new(source))

  it 'reads a balanced parenthesised body and consumes the closing paren' do
    scanner = StringScanner.new('echo (nested) done) rest')
    expect([described_class.new(scanner).parens, scanner.rest]).to eq(['echo (nested) done', ' rest'])
  end

  it 'reads a backtick body up to the closing backtick' do
    scanner = StringScanner.new('echo hi` rest')
    expect([described_class.new(scanner).backticks, scanner.rest]).to eq(['echo hi', ' rest'])
  end

  it 'raises on an unterminated $(' do
    expect { reader('echo no close').parens }.to raise_error(Rush::ParseError, /unterminated/)
  end

  it 'raises on an unterminated backtick' do
    expect { reader('echo no close').backticks }.to raise_error(Rush::ParseError, /unterminated/)
  end
end
