# frozen_string_literal: true

RSpec.describe Rush::ProgramReader do
  # A reader fed from a fixed list of lines; the block ignores the continuation
  # flag (only the REPL uses it, to choose PS1 vs PS2).
  def reader(*lines)
    queue = lines
    described_class.new { queue.shift }
  end

  it 'returns a parsed program for a complete command' do
    expect(reader("echo hi\n").next_program).to be_a(Rush::AST::List)
  end

  it 'signals :eof when the input is exhausted' do
    expect(reader.next_program).to eq(:eof)
  end

  it 'accumulates continuation lines until the construct is complete' do
    expect(reader("if true\n", "then echo ok\n", "fi\n").next_program).to be_a(Rush::AST::List)
  end

  it 'yields successive complete commands across calls, then :eof' do
    r = reader("echo a\n", "echo b\n")
    expect([r.next_program, r.next_program, r.next_program].last).to eq(:eof)
  end

  it 'finalises an unterminated here-document at end of input' do
    expect(reader("cat <<EOF\n", "body\n").next_program).to be_a(Rush::AST::List)
  end

  it 'raises a syntax error for an unterminated quote at end of input' do
    expect { reader("echo 'oops\n").next_program }.to raise_error(Rush::ParseError)
  end

  it 'raises a syntax error for an unexpected token' do
    expect { reader("bad )\n").next_program }.to raise_error(Rush::ParseError)
  end
end
