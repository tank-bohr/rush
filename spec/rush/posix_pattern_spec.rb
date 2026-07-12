# frozen_string_literal: true

RSpec.describe Rush::PosixPattern do
  def translate(pattern)
    described_class.new(pattern).source
  end

  it 'translates shell wildcards and anchors the whole value' do
    expect(translate('a*?b')).to eq('^a.*.b$')
  end

  it 'escapes ERE metacharacters that are shell literals' do
    expect(translate('a+b.(c)')).to eq('^a\\+b\\.\\(c\\)$')
  end

  it 'preserves POSIX bracket subforms and converts shell negation' do
    expect([translate('[[:alpha:]]'), translate('[[=a=]]'), translate('[[.ch.]]'), translate('[!a-c]')])
      .to eq(['^[[:alpha:]]$', '^[[=a=]]$', '^[[.ch.]]$', '^[^a-c]$'])
  end

  it 'broadens brackets without leaking Ruby recursive or brace glob syntax' do
    patterns = ['dir/[a-c][[:digit:]][[.ch.]]', '**/x', '[a]*/x', '{a,b}*']
    expect(patterns.map { |pattern| described_class.new(pattern).glob_source })
      .to eq(['dir/*', '*/x', '*/x', '\\{a,b\\}*'])
  end

  it 'keeps escaped shell metacharacters literal' do
    expect(translate('\\*\\?\\[')).to eq('^\\*\\?\\[$')
  end

  it 'moves shell-escaped bracket metacharacters to literal ERE positions' do
    expect([translate('[a\\]b[:digit:]]'), translate('[!a\\]]'),
            translate('[a\\-c]'), translate('[\\^a]'), translate('[\\\\a]'),
            translate('[\\[.ch.]]')])
      .to eq(['^[]ab[:digit:]]$', '^[^]a]$', '^[ac-]$', '^[a^]$', '^[\\a]$', '^[.ch.[]\\]$'])
  end
end
