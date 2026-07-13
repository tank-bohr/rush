# frozen_string_literal: true

RSpec.describe Rush::Builtins::ReadInput do
  def gather(text, raw: false)
    described_class.new(StringIO.new(text), raw).call
  end

  it 'reads one newline-terminated line as complete' do
    expect(gather("ab\n")).to eq([[['a', false], ['b', false]], true])
  end

  it 'waits for readable IO before consuming a physical line' do
    reader, writer = IO.pipe
    writer.write("ab\n")
    expect(described_class.new(reader, false).call).to eq([[['a', false], ['b', false]], true])
  ensure
    reader&.close
    writer&.close
  end

  it 'returns a partial IO line when EOF arrives without a newline' do
    reader, writer = IO.pipe
    writer.write('ab')
    writer.close
    expect(described_class.new(reader, false).call).to eq([[['a', false], ['b', false]], false])
  ensure
    reader&.close
    writer&.close unless writer&.closed?
  end

  it 'retries when readability races with a nonblocking read' do
    reader, writer = IO.pipe
    writer.write("a\n")
    original = reader.method(:read_nonblock)
    calls = 0
    allow(reader).to receive(:read_nonblock) do |*args|
      calls += 1
      raise IO::EAGAINWaitReadable if calls == 1

      original.call(*args)
    end
    expect(described_class.new(reader, false).call).to eq([[['a', false]], true])
  ensure
    reader&.close
    writer&.close
  end

  it 'annotates a backslash-escaped character and drops the backslash' do
    expect(gather("a\\ b\n")).to eq([[['a', false], [' ', true], ['b', false]], true])
  end

  it 'reads an escaped backslash as one literal, escaped backslash' do
    expect(gather("a\\\\b\n")).to eq([[['a', false], ['\\', true], ['b', false]], true])
  end

  it 'joins the next physical line onto a trailing unescaped backslash, leaving a joint' do
    expect(gather("a\\\nb\n")).to eq([[['a', false], ['', true], ['b', false]], true])
  end

  it 'joins across several continuation lines' do
    expect(gather("a\\\nb\\\nc\n"))
      .to eq([[['a', false], ['', true], ['b', false], ['', true], ['c', false]], true])
  end

  it 'consumes only the continuation lines it joins' do
    stdin = StringIO.new("a\\\nb\nc\n")
    expect(described_class.new(stdin, false).call).to eq([[['a', false], ['', true], ['b', false]], true])
    expect(stdin.gets).to eq("c\n")
  end

  it 'reports incomplete at end of file during a continuation' do
    expect(gather("a\\\n")).to eq([[['a', false], ['', true]], false])
  end

  it 'drops a trailing backslash at hard end of file and reports incomplete' do
    expect(gather('a\\')).to eq([[['a', false], ['', true]], false])
  end

  it 'reports a line without a newline terminator as incomplete' do
    expect(gather('abc')).to eq([[['a', false], ['b', false], ['c', false]], false])
  end

  it 'returns no characters and incomplete at end of file' do
    expect(gather('')).to eq([[], false])
  end

  it 'keeps backslashes verbatim in raw mode and never continues the line' do
    expect(gather("a\\\nb\n", raw: true)).to eq([[['a', false], ['\\', false]], true])
  end
end
