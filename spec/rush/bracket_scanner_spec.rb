# frozen_string_literal: true

RSpec.describe Rush::BracketScanner do
  def scan(source)
    described_class.new(source, 0).call
  end

  it 'finds ordinary and negated expression closes' do
    expect([scan('[a-c]tail'), scan('[!a]tail'), scan('[^]]tail')])
      .to eq([[5, false], [4, false], [4, false]])
  end

  it 'keeps an initial closing bracket as a member' do
    expect([scan('[]]tail'), scan('[!]]tail')]).to eq([[3, false], [4, false]])
  end

  it 'skips all three nested POSIX bracket forms atomically' do
    expect([scan('[[:alpha:]]x'), scan('[[=a=]]x'), scan('[[.x.]]x')])
      .to eq([[11, true], [7, true], [7, true]])
  end

  it 'does not close on an escaped member bracket' do
    source = '[a\\]b[:digit:]]'

    expect(scan(source)).to eq([source.length, true])
  end

  it 'finds a collation delimiter after a closing-bracket element' do
    expect([scan('[[.].]]'), scan('[[=]=]]')]).to eq([[7, true], [7, true]])
  end

  it 'honours a nonzero expression offset without finding an earlier delimiter' do
    expect(described_class.new(':]xx[[:alpha:]]tail', 4).call).to eq([15, true])
  end

  it 'does not treat a marker after an ordinary member as a nested opener' do
    expect(scan('[a:x:]tail')).to eq([6, false])
  end

  it 'returns no finish for an unclosed expression' do
    expect(scan('[abc')).to eq([nil, false])
  end
end
