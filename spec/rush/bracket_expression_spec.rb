# frozen_string_literal: true

RSpec.describe Rush::BracketExpression do
  def parse(source)
    described_class.parse(source, 0)
  end

  it 'finds the outer close past a nested POSIX class' do
    expression = parse('[a[:digit:]_]tail')
    offset = described_class.parse('xx[[:alpha:]]tail', 2)

    expect([expression&.source, expression&.finish, expression&.special?, offset&.source, offset&.finish])
      .to eq(['[a[:digit:]_]', 13, true, '[[:alpha:]]', 13])
  end

  it 'keeps and regexp-escapes an initial closing bracket' do
    expect([parse('[]]')&.source, parse('[]]')&.regex, parse('[!]]')&.source, parse('[!]]')&.regex])
      .to eq(['[]]', '[\\]]', '[!]]', '[^\\]]'])
  end

  it 'returns nil for an ordinary unclosed bracket' do
    expect(parse('[abc')).to be_nil
  end

  it 'keeps a malformed nested POSIX form as an unmatchable expression' do
    expression = parse('[[:alpha:]')

    expect([expression&.special?, expression&.finish, expression&.regex]).to eq([true, 10, '(?!)'])
  end

  it 'distinguishes an ordinary bracket from a POSIX nested subform' do
    ordinary = parse('[a-c]')
    special = parse('[[:digit:]]')

    expect([ordinary&.special?, ordinary&.glob_source, special&.glob_source]).to eq([false, '[a-c]', '?'])
  end

  it 'compiles named classes and shell negation to Ruby regexp syntax' do
    expect([parse('[[:alpha:]]')&.regex, parse('[![:digit:]]')&.regex,
            parse('[[:alpha:][:digit:]]')&.regex])
      .to eq(['[[:alpha:]]', '[^[:digit:]]', '[[:alpha:][:digit:]]'])
  end

  it 'follows dash in accepting the unspecified leading caret as negation' do
    expect(parse('[^a]')&.regex).to eq('[^a]')
  end

  it 'reduces and escapes portable one-character collation forms' do
    expect([parse('[[=a=]]')&.regex, parse('[[.x.]]')&.regex,
            parse('[[=a=][.b.]]')&.regex, parse('[[...]]')&.regex,
            parse('[[.[.]]')&.regex, parse('[[.].]]')&.regex])
      .to eq(['[a]', '[x]', '[ab]', '[\\.]', '[\\[]', '[\\]]'])
  end

  it 'escapes ordinary opening brackets inside an extended expression' do
    expect(parse('[[a[[:digit:]]')&.regex).to eq('[\\[a\\[[:digit:]]')
  end

  it 'appends its regexp/glob forms and advances the host scanner' do
    expression = parse('[[:digit:]]tail')
    scanner = StringScanner.new('[[:digit:]]tail')
    regexp = +'pre'
    glob = +'path'
    expression&.append_to(regexp, glob, scanner)

    expect([regexp, glob, scanner.pos]).to eq(['pre[[:digit:]]', 'path?', 11])
  end

  it 'makes an unknown class or multi-character collating symbol unmatchable' do
    expect([parse('[[:unknown:]]')&.regex, parse('[[.ch.]]')&.regex]).to eq(['(?!)', '(?!)'])
  end
end
