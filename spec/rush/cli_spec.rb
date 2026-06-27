# frozen_string_literal: true

RSpec.describe Rush::CLI do
  def run(argv, system) = described_class.run(argv, system: system)

  it 'runs a -c command and returns its exit code' do
    expect(run(['-c', 'exit 4'], FakeSystemCalls.new)).to eq(4)
  end

  it 'executes commands and returns the final status' do
    system = FakeSystemCalls.new
    expect(run(['-c', 'echo hi'], system)).to eq(0)
    expect(system.stdout.string).to eq("hi\n")
  end

  it 'reads the program from stdin when given no -c' do
    system = FakeSystemCalls.new(stdin: "echo fromstdin\n")
    run([], system)
    expect(system.stdout.string).to eq("fromstdin\n")
  end

  it 'reports parse errors on stderr and returns 2' do
    system = FakeSystemCalls.new
    allow(Rush::Parser).to receive(:new).and_raise(Rush::ParseError, 'boom')
    expect(run(['-c', 'whatever'], system)).to eq(2)
    expect(system.stderr.string).to include('boom')
  end

  it 'treats an empty program as a success' do
    expect(run(['-c', ''], FakeSystemCalls.new)).to eq(0)
  end

  it 'defaults to the real system calls when none is injected' do
    expect(described_class.run(['-c', ':'])).to eq(0)
  end
end
