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

  it 'starts an interactive REPL with no arguments on a terminal' do
    system = FakeSystemCalls.new(stdin: "echo hi\n", tty: true)
    expect(run([], system)).to eq(0)
    expect(system.stdout.string).to eq("hi\n")
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

  it 'treats break outside a loop as a no-op' do
    expect(run(['-c', 'break'], FakeSystemCalls.new)).to eq(0)
  end

  it 'treats return outside a function as a no-op' do
    expect(run(['-c', 'return'], FakeSystemCalls.new)).to eq(0)
  end

  it 'reports a readonly violation on stderr and returns 2' do
    system = FakeSystemCalls.new
    expect(run(['-c', 'readonly x=1; x=2'], system)).to eq(2)
    expect(system.stderr.string).to include('read only')
  end

  it 'fires the EXIT trap after the program completes' do
    system = FakeSystemCalls.new
    expect(run(['-c', "trap 'echo bye' EXIT; echo body"], system)).to eq(0)
    expect(system.stdout.string).to eq("body\nbye\n")
  end

  it 'publishes the exiting status as $? inside the EXIT trap' do
    system = FakeSystemCalls.new
    run(['-c', "trap 'echo rc=$?' EXIT; false"], system)
    expect(system.stdout.string).to eq("rc=1\n")
  end

  it 'lets the EXIT trap override the exit code by running exit' do
    expect(run(['-c', "trap 'exit 9' EXIT; exit 2"], FakeSystemCalls.new)).to eq(9)
  end

  it 'ignores a syntax error in the EXIT trap action' do
    system = FakeSystemCalls.new
    expect(run(['-c', "trap 'fi' EXIT; echo body"], system)).to eq(0)
    expect(system.stdout.string).to eq("body\n")
  end

  it 'defaults to the real system calls when none is injected' do
    expect(described_class.run(['-c', ':'])).to eq(0)
  end

  it 'runs commands before a later syntax error, then aborts with 2' do
    system = FakeSystemCalls.new
    expect(run(['-c', "echo one\nbad )\necho two"], system)).to eq(2)
    expect(system.stdout.string).to eq("one\n")
  end

  it 'preserves $? across a blank line between commands' do
    system = FakeSystemCalls.new
    run(['-c', "false\n\necho $?"], system)
    expect(system.stdout.string).to eq("1\n")
  end

  it 'fires the EXIT trap on a syntax error, with $? set to 2' do
    system = FakeSystemCalls.new
    expect(run(['-c', "trap 'echo rc=$?' EXIT\ntrue\nbad )"], system)).to eq(2)
    expect(system.stdout.string).to eq("rc=2\n")
  end

  it 'fires the EXIT trap on a readonly violation' do
    system = FakeSystemCalls.new
    run(['-c', "trap 'echo bye' EXIT\nreadonly x=1\nx=2"], system)
    expect(system.stdout.string).to eq("bye\n")
  end

  it 'lets the EXIT trap override the exit code after a syntax error' do
    expect(run(['-c', "trap 'exit 9' EXIT\necho one\nbad )"], FakeSystemCalls.new)).to eq(9)
  end

  it 'expands an alias defined by an earlier line' do
    system = FakeSystemCalls.new
    run(['-c', "alias g=echo\ng hello"], system)
    expect(system.stdout.string).to eq("hello\n")
  end

  it 'does not expand an alias defined on the same line' do
    external = instance_double(Rush::External, call: Rush::Status.failure(127))
    allow(Rush::External).to receive(:new).and_return(external)
    expect(run(['-c', 'alias g=echo; g hello'], FakeSystemCalls.new)).to eq(127)
    expect(Rush::External).to have_received(:new).with(anything, %w[g hello], anything, anything)
  end

  it 'bakes an alias into a function body parsed after the definition' do
    system = FakeSystemCalls.new
    run(['-c', "alias g=echo\nf() { g fromfunc; }\nf"], system)
    expect(system.stdout.string).to eq("fromfunc\n")
  end
end
