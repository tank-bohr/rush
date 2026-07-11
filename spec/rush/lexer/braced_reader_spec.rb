# frozen_string_literal: true

RSpec.describe Rush::Lexer::BracedReader do
  def read(source, quoted: false, error: Rush::ParseError)
    scanner = StringScanner.new(source)
    body = described_class.new(scanner, error: error, quoted: quoted).read
    [body, scanner.rest]
  end

  it 'reads a plain body and consumes the closing brace' do
    expect(read('x:-fallback} rest')).to eq(['x:-fallback', ' rest'])
  end

  it 'reads a nested ${...} through its own closing brace' do
    expect(read('a:-${b:-${c}}}!')).to eq(['a:-${b:-${c}}', '!'])
  end

  it 'keeps a bare { ordinary' do
    expect(read('a:-{}')).to eq(['a:-{', ''])
  end

  it 'skips a } inside single quotes' do
    expect(read("a:-'}'}rest")).to eq(["a:-'}'", 'rest'])
  end

  it 'skips a } inside double quotes' do
    expect(read('a:-"}"}r')).to eq(['a:-"}"', 'r'])
  end

  it 'skips an escaped quote inside double quotes' do
    expect(read('a:-"\\"}"}.')).to eq(['a:-"\\"}"', '.'])
  end

  it 'skips a backslash-escaped }' do
    expect(read('a:-\\}}')).to eq(['a:-\\}', ''])
  end

  it 'skips a } inside a command substitution' do
    expect(read('a:-$(echo })}')).to eq(['a:-$(echo })', ''])
  end

  it 'skips a } inside a command substitution with nested parens' do
    expect(read('a:-$( (echo }) )}')).to eq(['a:-$( (echo }) )', ''])
  end

  it 'reads an arithmetic substitution whole' do
    expect(read('a:-$((1+2))}')).to eq(['a:-$((1+2))', ''])
  end

  it 'skips a } inside backticks' do
    expect(read('a:-`echo }`}')).to eq(['a:-`echo }`', ''])
  end

  it 'keeps a $ that begins no substitution literal' do
    expect(read('a:-$}')).to eq(['a:-$', ''])
  end

  it 'treats a single quote as ordinary in a quoted context' do
    expect(read("a:-'}x}", quoted: true)).to eq(["a:-'", 'x}'])
  end

  it 'raises the given error on an unterminated body' do
    expect { read('a:-${b', error: Rush::IncompleteInput) }
      .to raise_error(Rush::IncompleteInput, /unterminated \$\{/)
  end

  it 'raises on an unterminated single quote' do
    expect { read("a:-'x") }.to raise_error(Rush::ParseError, /unterminated single quote/)
  end

  it 'raises on an unterminated double quote' do
    expect { read('a:-"x') }.to raise_error(Rush::ParseError, /unterminated double quote/)
  end

  it 'raises on a trailing backslash' do
    expect { read('a:-\\') }.to raise_error(Rush::ParseError, /unterminated \$\{/)
  end
end
