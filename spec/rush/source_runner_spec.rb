# frozen_string_literal: true

RSpec.describe Rush::SourceRunner do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def run(text)
    described_class.new(executor, text).run
  end

  def out
    system.stdout.string
  end

  it 'runs the commands in order in the current shell' do
    run("echo a\necho b\n")
    expect(out).to eq("a\nb\n")
  end

  it 'lets a command shape how the next line is parsed (alias takes effect)' do
    run("alias g=echo\ng hi\n")
    expect(out).to eq("hi\n")
  end

  it 'persists definitions and assignments into the shell state' do
    run("X=set\nf() { :; }\n")
    expect(state.environment.get('X')).to eq('set')
    expect(state.functions.key?('f')).to be(true)
  end

  it 'returns success for empty input regardless of the prior status' do
    state.record_status(Rush::Status.new(1))
    expect(run('')).to be_success
  end

  it 'returns success for comment-only input (no command ran)' do
    state.record_status(Rush::Status.new(1))
    expect(run("# just a comment\n")).to be_success
  end

  it 'returns the status of the last non-empty command' do
    expect(run("true\nfalse\n")).not_to be_success
  end

  it 'preserves the last command status across a trailing blank line' do
    expect(run("false\n\n")).not_to be_success
  end

  it 'keeps $? live for the body (the commands inherit the current status)' do
    state.record_status(Rush::Status.new(1))
    run("echo $?\n")
    expect(out).to eq("1\n")
  end

  it 'runs the earlier commands before a later syntax error, then raises' do
    expect { run("echo a\nbad )\n") }.to raise_error(Rush::ParseError)
    expect(out).to eq("a\n")
  end

  it 'accumulates a multi-line construct until it is complete' do
    run("if true\nthen echo ok\nfi\n")
    expect(out).to eq("ok\n")
  end

  it 'propagates exit from the input' do
    expect { run("exit 4\n") }.to raise_error(Rush::ExitSignal) { |e| expect(e.code).to eq(4) }
  end

  it 'propagates a return signal (eval relies on this; dot catches it)' do
    expect { run("return 2\n") }.to raise_error(Rush::ReturnSignal) { |e| expect(e.code).to eq(2) }
  end
end
