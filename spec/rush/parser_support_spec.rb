# frozen_string_literal: true

RSpec.describe Rush::ParserSupport do
  subject(:parser) { Rush::Parser.new(Rush::Lexer.new('')) }

  it 'parses a token stream into an AST sequence' do
    program = Rush::Parser.new(Rush::Lexer.new('echo hi')).parse
    expect(program).to be_a(Rush::AST::Sequence)
    expect(program.commands.size).to eq(1)
  end

  it 'raises a ParseError naming a word value' do
    expect { parser.on_error(0, Rush::AST::Word.literal('oops'), []) }
      .to raise_error(Rush::ParseError, /oops/)
  end

  it 'raises a ParseError naming an operator value' do
    expect { parser.on_error(0, ';', []) }.to raise_error(Rush::ParseError, /;/)
  end
end
