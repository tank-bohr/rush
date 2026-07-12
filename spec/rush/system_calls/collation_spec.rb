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
    skip 'glibc collation backend unavailable' unless collation.available?

    expect(collation.match_shell?('[[:digit:]]', '5', %w[C C]) { false }).to be(true)
    expect(collation.match_shell?('[[:digit:]]', 'x', %w[C C]) { true }).to be(false)
    expect(collation.match_shell?('[\\[.ch.]]', 'ch', %w[C C]) { true }).to be(false)
    expect(collation.match_shell?('[\\[.ch.]]', 'c]', %w[C C]) { false }).to be(true)
    expect(collation.compare('a', 'b', %w[C C])).to be_negative
  end

  it 'treats an invalid native bracket expression as no match' do
    skip 'glibc collation backend unavailable' unless collation.available?

    expect(collation.match_shell?('[[:unknown:]]', 'x', %w[C C]) { true }).to be(false)
  end
end
