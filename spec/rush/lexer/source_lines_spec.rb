# frozen_string_literal: true

require 'strscan'

RSpec.describe Rush::Lexer::SourceLines do
  def word(lines, scanner, pattern)
    lines.word do
      scanner.scan(pattern)
      Rush::AST::Word.new([])
    end
  end

  it 'stamps each word with its start line, counting only its own newlines' do
    scanner = StringScanner.new("ab\ncd\nef")
    lines = described_class.new(scanner, 0)
    stamped = [word(lines, scanner, /ab\nc/), word(lines, scanner, /d\ne/), word(lines, scanner, /f/)]
    expect(stamped.map(&:source_line)).to eq([1, 2, 3])
  end

  it 'starts numbering from the given line offset' do
    scanner = StringScanner.new('x')
    lines = described_class.new(scanner, 4)
    expect(word(lines, scanner, /x/).source_line).to eq(5)
  end

  it 'returns the scanned word restamped, segments intact' do
    scanner = StringScanner.new('hi')
    lines = described_class.new(scanner, 0)
    scanned = lines.word do
      scanner.scan('hi')
      Rush::AST::Word.literal('hi', source_line: 9)
    end
    expect([scanned.literal_text, scanned.source_line]).to eq(['hi', 1])
  end

  it 'advances past a heredoc body plus the newline that triggered it' do
    scanner = StringScanner.new("cat\nbody\nEOF\nnext")
    lines = described_class.new(scanner, 0)
    word(lines, scanner, /cat/)
    scanner.scan("\n")
    start = scanner.pos
    scanner.scan("body\nEOF\n")
    lines.heredoc_newline(start)
    expect(word(lines, scanner, /next/).source_line).to eq(4)
  end
end
