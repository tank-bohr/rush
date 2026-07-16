# frozen_string_literal: true

RSpec.describe Rush::SystemCalls::Collation do
  subject(:collation) { described_class.new }

  it 'falls back cleanly when the native function table is unavailable' do
    fallback = described_class.allocate
    fallback.instance_variable_set(:@functions, {})
    expect(fallback.match_shell?('*', 'x', %w[C C]) { true }).to be(true)
    expect(fallback.glob('*', %w[C C]) { ['fallback'] }).to eq(['fallback'])
  end

  it 'matches POSIX ERE brackets and compares strings through glibc' do
    skip 'glibc collation backend unavailable' unless glibc?

    expect(collation.match_shell?('[[:digit:]]', '5', %w[C C]) { false }).to be(true)
    expect(collation.match_shell?('[[:digit:]]', 'x', %w[C C]) { true }).to be(false)
    expect(collation.match_shell?('[\\[.ch.]]', 'ch', %w[C C]) { true }).to be(false)
    expect(collation.match_shell?('[\\[.ch.]]', 'c]', %w[C C]) { false }).to be(true)
    expect(collation.compare('a', 'b', %w[C C])).to be_negative
  end

  it 'treats an invalid native bracket expression as no match' do
    skip 'glibc collation backend unavailable' unless glibc?

    expect(collation.match_shell?('[[:unknown:]]', 'x', %w[C C]) { true }).to be(false)
  end

  it 'matches a raw POSIX ERE and rejects both a non-match and an uncompilable regex' do
    skip 'glibc collation backend unavailable' unless glibc?

    expect(collation.match?('^a.c$', 'abc', %w[C C])).to be(true)
    expect(collation.match?('^a.c$', 'axd', %w[C C])).to be(false)
    expect(collation.match?('[', 'x', %w[C C])).to be(false)
  end

  it 'globs candidates, filters them through the locale match, and sorts by strcoll' do
    skip 'glibc collation backend unavailable' unless glibc?

    Dir.mktmpdir do |dir|
      %w[b.txt a.txt c.md].each { |name| File.write(File.join(dir, name), '') }

      expect(collation.glob("#{dir}/*.txt", %w[C C]) { %w[fallback-taken] })
        .to eq([File.join(dir, 'a.txt'), File.join(dir, 'b.txt')])
      expect(collation.glob("#{dir}/*.rb", %w[C C]) { %w[fallback-taken] }).to eq([])
    end
  end

  it 'compares byte order both ways with a byte tie-break at strcoll zero' do
    skip 'glibc collation backend unavailable' unless glibc?

    expect(collation.compare('b', 'a', %w[C C])).to be_positive
    expect(collation.compare('same', 'same', %w[C C])).to eq(0)
  end

  it 'falls back to the C locale when the requested locale cannot be installed' do
    skip 'glibc collation backend unavailable' unless glibc?

    expect(collation.match?('^a$', 'a', ['no-such-locale.XX', 'no-such-locale.XX'])).to be(true)
  end

  it 'installs LC_CTYPE from the second setting, distinguishable from LC_COLLATE' do
    skip 'glibc collation backend unavailable' unless glibc?
    skip 'C.UTF-8 locale unavailable' unless c_utf8?

    expect(collation.match?('^[[:alpha:]]$', 'é', %w[C C.UTF-8])).to be(true)
    expect(collation.match?('^[[:alpha:]]$', 'é', %w[C.UTF-8 C])).to be(false)
    expect(collation.match?('^[[:alpha:]]$', 'é', ['C', 'no-such-locale.XX'])).to be(false)
  end

  it 'resolves settings from LC_ALL over the category over LANG, skipping empties' do
    with_env('LC_ALL' => 'aa', 'LC_COLLATE' => 'cc', 'LC_CTYPE' => 'tt', 'LANG' => 'll') do
      expect(collation.default_settings).to eq(%w[aa aa])
    end
    with_env('LC_ALL' => '', 'LC_COLLATE' => 'cc', 'LC_CTYPE' => nil, 'LANG' => 'll') do
      expect(collation.default_settings).to eq(%w[cc ll])
    end
  end

  it 'defaults every unset or empty category to C' do
    with_env('LC_ALL' => nil, 'LC_COLLATE' => '', 'LC_CTYPE' => nil, 'LANG' => '') do
      expect(collation.default_settings).to eq(%w[C C])
    end
  end

  # The guard must not consult the class under test: a mutation that breaks
  # Collation#available? would otherwise skip every guarded example and
  # survive on the unguarded remainder (how 112 mutants hid, rush-tqq).
  def glibc?
    Fiddle::Handle::DEFAULT['gnu_get_libc_version']
    true
  rescue Fiddle::DLError
    false
  end

  # Probed via locale -a, not through the class under test (see glibc?).
  def c_utf8?
    `locale -a 2>/dev/null`.split.any? { |name| name.match?(/\AC\.utf-?8\z/i) }
  end

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end
end
