# frozen_string_literal: true

RSpec.describe Rush::Repl do
  def session(input)
    system = FakeSystemCalls.new(stdin: input)
    code = described_class.new(system).run
    [system.stdout.string, system.stderr.string, code]
  end

  it 'runs each line against one persistent state' do
    out, = session("x=5\necho $x\n")
    expect(out).to eq("5\n")
  end

  it 'continues an unfinished compound command, prompting with PS2' do
    out, err = session("if true\nthen echo ok\nfi\n")
    expect([out, err.include?('> ')]).to eq(["ok\n", true])
  end

  it 'continues a backslash-ended line, prompting with PS2' do
    out, err = session("echo a \\\nb\n")
    expect([out, err]).to eq(["a b\n", '$ > $ '])
  end

  it 'continues an unterminated quote across lines' do
    out, = session("echo 'a\nb'\n")
    expect(out).to eq("a\nb\n")
  end

  it 'continues a here-document until its delimiter' do
    out, = session("read v <<END\nhi\nEND\necho \"[$v]\"\n")
    expect(out).to eq("[hi]\n")
  end

  it 'reports a syntax error and keeps the session alive' do
    out, err = session("fi\necho after\n")
    expect([out, err.include?('syntax error')]).to eq(["after\n", true])
  end

  it 'exits with the status given to exit' do
    expect(session("echo hi\nexit 7\necho never\n")).to eq(["hi\n", '$ $ ', 7])
  end

  it 'prompts from the PS1/PS2 variables, re-reading them each time' do
    _, err = session("PS1='[$?]> '\nfalse\nif true\nthen echo ok\nfi\n")
    expect(err).to eq('$ [0]> [1]> > > [0]> ')
  end

  it 'returns the last command status at end of input' do
    _, _, code = session("false\n")
    expect(code).to eq(1)
  end

  it 'treats a stray break outside a loop as a no-op' do
    out, = session("break\necho after\n")
    expect(out).to eq("after\n")
  end

  it 'treats a top-level return as a no-op, keeping the session alive' do
    out, = session("return 3\necho after\n")
    expect(out).to eq("after\n")
  end

  it 'reports an expansion error without ending the session' do
    out, err = session("set -u\necho $missing\necho after\n")
    expect([out, err.include?('missing')]).to eq(["after\n", true])
  end

  it 'publishes status 2 as $? after a reported error, like a batch abort' do
    out, = session("readonly x=1\nx=2\necho [$?]\nfi\necho [$?]\n")
    expect(out).to eq("[2]\n[2]\n")
  end

  it 'installs the interactive signal handlers when the state is interactive' do
    system = FakeSystemCalls.new(stdin: '')
    state = Rush::ShellState.new
    state.set_option(:interactive, true)
    described_class.new(system, state: state).run
    expect(system.traps_installed.map(&:first)).to include('INT', 'QUIT', 'TERM')
    expect { system.trap_block('INT').call(2) }.to raise_error(Rush::Interrupted)
    expect([system.trap_block('QUIT').call(3), system.trap_block('TERM').call(15)]).to eq([nil, nil])
  end

  it 'turns an interrupt while reading into $?=130 and a fresh prompt' do
    system = FakeSystemCalls.new
    reads = [-> { raise Rush::Interrupted, 'interrupted' }, -> { "echo [$?]\n" }, -> {}]
    allow(system).to receive(:read_line) { reads.shift.call }
    code = described_class.new(system).run
    expect([system.stdout.string, code]).to eq(["[130]\n", 0])
  end

  it 'turns an interrupt during a command into $?=130, keeping the session' do
    system = FakeSystemCalls.new(stdin: "sleepy\necho [$?]\n")
    allow(Rush::External).to receive(:new).and_raise(Rush::Interrupted, 'interrupted')
    code = described_class.new(system).run
    expect([system.stdout.string, code]).to eq(["[130]\n", 0])
  end

  it 'reports a broken startup file and still serves the session' do
    system = FakeSystemCalls.new(stdin: "echo main [$?]\n")
    system.provide_file('/etc/profile', "bad )\n")
    startup = Rush::Startup.new(login: true, interactive: true)
    code = described_class.new(system, startup: startup).run
    expect([system.stdout.string, system.stderr.string.include?('syntax'), code])
      .to eq(["main [2]\n", true, 0])
  end

  it 'fires the EXIT trap when the session ends at end of input' do
    out, = session("trap 'echo bye' EXIT\necho body\n")
    expect(out).to eq("body\nbye\n")
  end

  it 'fires the EXIT trap when the session ends via exit' do
    out, _, code = session("trap 'echo bye' EXIT\nexit 3\n")
    expect([out, code]).to eq(["bye\n", 3])
  end
end
