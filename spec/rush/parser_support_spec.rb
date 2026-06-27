# frozen_string_literal: true

RSpec.describe Rush::ParserSupport do
  subject(:parser) { Rush::Parser.new(Rush::Lexer.new('')) }

  def parse(source) = Rush::Parser.new(Rush::Lexer.new(source)).parse
  def first_command(source) = parse(source).entries.first.and_or.commands.first

  it 'parses an empty program into an empty list' do
    expect(parse('').entries).to be_empty
  end

  it 'builds and-or, async and sequence entries' do
    list = parse('a && b; c & d')
    expect(list.entries.map(&:async)).to eq([false, true, false])
    expect(list.entries.first.and_or).to be_a(Rush::AST::AndOr)
  end

  it 'partitions assignments, argv words and redirects of a simple command' do
    command = first_command('X=1 echo hi > out')
    expect(command.assignments.map(&:name)).to eq(['X'])
    expect(command.words.map(&:literal_text)).to eq(%w[echo hi])
    expect(command.redirects.map(&:kind)).to eq([:out])
  end

  it 'captures an explicit fd as the redirect io_number' do
    expect(first_command('cat 2> err').redirects.first.io_number).to eq(2)
  end

  it 'parses an if clause and a brace group' do
    expect(first_command('if true; then echo hi; fi')).to be_a(Rush::AST::If)
    expect(first_command('{ echo hi; }')).to be_a(Rush::AST::BraceGroup)
  end

  it 'parses a negated pipeline' do
    expect(parse('! false').entries.first.and_or.negate).to be(true)
  end

  it 'parses while and until loops' do
    expect(first_command('while true; do :; done')).to be_a(Rush::AST::While)
    expect(first_command('until true; do :; done')).to be_a(Rush::AST::Until)
  end

  it 'raises a ParseError naming a word value' do
    expect { parser.on_error(0, Rush::AST::Word.literal('oops'), []) }
      .to raise_error(Rush::ParseError, /oops/)
  end

  it 'raises a ParseError naming an operator value' do
    expect { parser.on_error(0, ';', []) }.to raise_error(Rush::ParseError, /;/)
  end
end
