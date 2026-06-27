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

  it 'raises a ParseError naming a word value' do
    expect { parser.on_error(0, Rush::AST::Word.literal('oops'), []) }
      .to raise_error(Rush::ParseError, /oops/)
  end

  it 'raises a ParseError naming an operator value' do
    expect { parser.on_error(0, ';', []) }.to raise_error(Rush::ParseError, /;/)
  end
end
