# frozen_string_literal: true

RSpec.describe Rush::ShellPattern do
  def pattern(source)
    described_class.new(source)
  end

  it 'leaves ordinary matching on Ruby fnmatch semantics' do
    matcher = pattern('a*[!x]')

    expect([matcher.extended?, matcher.glob_source, matcher.match?('abc'), matcher.match?('abx'),
            pattern('*').match?('.hidden')]).to eq([false, 'a*[!x]', true, false, true])
  end

  it 'matches named classes, mixtures and negation' do
    expect([pattern('[[:alpha:]]').match?('é'), pattern('[a[:digit:]_]').match?('5'),
            pattern('[![:digit:]]').match?('x'), pattern('[![:digit:]]').match?('5')])
      .to eq([true, true, true, false])
  end

  it 'supports all twelve mandatory POSIX character classes' do
    members = { alnum: '7', alpha: 'a', blank: "\t", cntrl: "\u0001", digit: '7', graph: '!',
                lower: 'a', print: ' ', punct: '!', space: "\n", upper: 'A', xdigit: 'f' }

    expect(members).to all(satisfy { |name, member| pattern("[[:#{name}:]]").match?(member) })
  end

  it 'matches one-character equivalence and collating symbols' do
    expect([pattern('[[=a=]]').match?('a'), pattern('[[.x.]]').match?('x'),
            pattern('[[.[.]]').match?('['), pattern('[[.].]]').match?(']')]).to all(be(true))
  end

  it 'combines POSIX brackets with literals, ranges and both wildcards' do
    matcher = pattern('pre[a-c][[:digit:]]?*')

    expect([matcher.match?('preb5-tail'), matcher.match?('preb5'), matcher.match?('pred5-tail'),
            pattern('[[]*[[:digit:]]').match?('[x5')]).to eq([true, false, false, true])
  end

  it 'lets star span a newline like File.fnmatch' do
    expect(pattern('[[:alpha:]]*').match?("a\nb")).to be(true)
  end

  it 'matches initial closing-bracket members without regexp warnings' do
    matches = nil
    probe = lambda do
      matches = [pattern('[[:digit:]][]]').match?('5]'), pattern('[[:digit:]][!]]').match?('5x')]
    end
    expect(&probe).not_to output.to_stderr
    expect(matches).to eq([true, true])
  end

  it 'honours backslash escapes in and around an extended bracket' do
    matcher = pattern('\\*[[:digit:]]')
    bracket = pattern('[a\\]b[:digit:]]')

    expect([matcher.glob_source, matcher.match?('*7'), matcher.match?('x7'),
            bracket.match?(']'), bracket.match?('x')]).to eq(['\\*?', true, false, true, false])
  end

  it 'treats an unclosed bracket and trailing backslash as ordinary syntax' do
    expect([pattern('[abc').glob_source, pattern('[[:digit:]]\\').match?('5\\')]).to eq(['[abc', true])
  end

  it 'broadens only POSIX bracket subforms for pathname candidate discovery' do
    matcher = pattern('dir/[a-c][[:digit:]][[=x=]]')
    trailing_ordinary = pattern('[[:digit:]][a]')

    expect([matcher.extended?, matcher.glob_source, trailing_ordinary.extended?, trailing_ordinary.glob_source])
      .to eq([true, 'dir/[a-c]??', true, '?[a]'])
  end

  it 'returns false for invalid classes, collation and regexp ranges' do
    expect([pattern('[[:unknown:]]').match?('x'), pattern('[[.ch.]]').match?('ch'),
            pattern('[z-a][[:digit:]]').match?('z5')]).to eq([false, false, false])
  end

  it 'exposes matching through case equality for Enumerable#grep' do
    expect(%w[5 x].grep(pattern('[[:digit:]]'))).to eq(['5'])
  end
end
