# frozen_string_literal: true

RSpec.describe Rush::Builtins::FdOperand do
  let(:system) { FakeSystemCalls.new }
  let(:io) { Rush::IoTable.standard(system) }

  def resolver(table = io)
    described_class.new(table)
  end

  it 'leaves fake streams and absent descriptors for the existing port to answer' do
    expect(resolver.resolve('-t', '1')).to eq('1')
    expect(resolver.resolve('-p', '/dev/fd/9')).to eq('/dev/fd/9')
  end

  it 'rewrites -t and fd paths to a bound stream real descriptor' do
    read, write = IO.pipe
    bound = io.with(0, read).with(5, write)
    expect(resolver(bound).resolve('-t', ' 0')).to eq(read.fileno.to_s)
    expect(resolver(bound).resolve('-p', '/dev/stdin')).to eq("/dev/fd/#{read.fileno}")
    expect(resolver(bound).resolve('-p', '/proc/self/fd/5')).to eq("/dev/fd/#{write.fileno}")
  ensure
    read&.close
    write&.close
  end

  it 'makes an explicitly closed descriptor unmatchable' do
    closed = io.with_closed(1)
    expect(resolver(closed).resolve('-t', '1')).to eq('-1')
    expect(resolver(closed).resolve('-e', '/dev/stdout')).to eq('/dev/fd/-')
  end

  it 'leaves malformed -t operands and symlink primaries untouched' do
    closed = io.with_closed(1)
    expect(resolver(closed).resolve('-t', 'x')).to eq('x')
    expect(resolver(closed).resolve('-L', '/dev/stdout')).to eq('/dev/stdout')
    expect(resolver(closed).resolve('-h', '/dev/fd/1')).to eq('/dev/fd/1')
  end
end
