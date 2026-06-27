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

  it 'returns the last command status at end of input' do
    _, _, code = session("false\n")
    expect(code).to eq(1)
  end

  it 'treats a loop-control signal outside a loop as a no-op' do
    out, = session("break\necho after\n")
    expect(out).to eq("after\n")
  end

  it 'reports an expansion error without ending the session' do
    out, err = session("set -u\necho $missing\necho after\n")
    expect([out, err.include?('missing')]).to eq(["after\n", true])
  end
end
