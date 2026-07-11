# frozen_string_literal: true

RSpec.describe Rush::Lexer::SubstitutionReader do
  def reader(source)
    described_class.new(StringScanner.new(source))
  end

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

  it 'reads an arithmetic body up to the matching )) with balanced inner parens' do
    scanner = StringScanner.new('(1+2) * 3)) rest')
    expect([described_class.new(scanner).arithmetic, scanner.rest]).to eq(['(1+2) * 3', ' rest'])
  end

  it 'raises IncompleteInput on an unterminated arithmetic body' do
    expect { reader('1 + 2').arithmetic }.to raise_error(Rush::IncompleteInput, /unterminated/)
  end

  it 'raises a ParseError when the arithmetic body is malformed' do
    expect { reader('1 + 2) x').arithmetic }.to raise_error(Rush::ParseError, /malformed/)
  end

  # The arithmetic reader stays quote-blind by design: POSIX arithmetic has
  # no string syntax, and dash also rejects quotes here, so a `)` inside
  # quotes still counts. Both shells end with empty stdout and status 2.
  it 'counts a quoted paren in an arithmetic body (dash errors here too)' do
    expect { reader('"a)b"))').arithmetic }.to raise_error(Rush::ParseError)
  end
end
