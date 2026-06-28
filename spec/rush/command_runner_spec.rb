# frozen_string_literal: true

RSpec.describe Rush::CommandRunner do
  let(:system) { FakeSystemCalls.new }
  let(:env) { Rush::Environment.new({}) }
  let(:state) { Rush::ShellState.new(environment: env) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def word(text) = Rush::AST::Word.literal(text)
  def assignment(name, text) = Rush::AST::Assignment.new(name: name, value: word(text))
  def simple(assignments: [], words: [], redirects: []) = Rush::AST::SimpleCommand.new(assignments, words, redirects)
  def run(command) = described_class.new(executor, command).call

  def program(source) = Rush::Parser.new(Rush::Lexer.new(source)).parse

  it 'persists bare assignments and returns success' do
    expect(run(simple(assignments: [assignment('X', '1')]))).to be_success
    expect(env.get('X')).to eq('1')
  end

  it 'takes the last command substitution status for a no-command-word command' do
    system.wait_status = FakeSystemCalls::ChildStatus.new(4)
    expect(executor.run(program('x=$(cmd)')).exitstatus).to eq(4)
  end

  it 'reports success for a substitution-free assignment despite a prior failure' do
    state.record_status(Rush::Status.failure(9))
    expect(executor.run(program('x=plain'))).to be_success
  end

  it 'dispatches to a matching builtin' do
    expect(run(simple(words: [word('true')]))).to be_success
  end

  it 'dispatches to an external when no builtin matches, exporting prefix assignments' do
    captured = nil
    external = instance_double(Rush::External, call: Rush::Status.success)
    allow(Rush::External).to receive(:new) { |*args| captured = args }.and_return(external)
    run(simple(assignments: [assignment('X', '1')], words: [word('ls')]))
    expect(captured[3]).to include('X' => '1')
  end

  it 'applies redirections into the command io table' do
    redirect = Rush::AST::Redirect.new(kind: :out, target: word('/f'), io_number: nil)
    run(simple(words: [word('true')], redirects: [redirect]))
    expect(system.files).to have_key('/f')
  end

  it 'raises a redirect error on a failed open without trying to close anything' do
    allow(system).to receive(:close_redirect)
    allow(system).to receive(:open_file).and_raise(Errno::EACCES)
    redirect = Rush::AST::Redirect.new(kind: :out, target: word('/denied'), io_number: nil)
    expect { run(simple(words: [word('true')], redirects: [redirect])) }.to raise_error(Rush::RedirectError)
    expect(system).not_to have_received(:close_redirect)
  end

  it 'escalates a redirect-open failure on a special builtin to a fatal builtin error' do
    allow(system).to receive(:open_file).and_raise(Errno::ENOENT)
    redirect = Rush::AST::Redirect.new(kind: :out, target: word('/denied'), io_number: nil)
    expect { run(simple(words: [word(':')], redirects: [redirect])) }.to raise_error(Rush::BuiltinError)
  end

  it 'fails with status 1 when a builtin writes to a fd closed by >&-' do
    redirect = Rush::AST::Redirect.new(kind: :dup_out, target: word('-'), io_number: nil)
    expect(run(simple(words: [word('echo'), word('hi')], redirects: [redirect])).exitstatus).to eq(1)
  end

  it 'commits redirect-only exec and leaves its opened file open so it persists' do
    allow(system).to receive(:close_redirect)
    redirect = Rush::AST::Redirect.new(kind: :out, target: word('/f'), io_number: nil)
    run(simple(words: [word('exec')], redirects: [redirect]))
    expect(executor.io.get(1)).to be(system.files['/f'])
    expect(system).not_to have_received(:close_redirect)
  end

  it 'binds a redirect on a function call to the function body' do
    state.functions.define('f', Rush::AST::SimpleCommand.new([], [word('echo'), word('body')], []))
    redirect = Rush::AST::Redirect.new(kind: :out, target: word('/f.txt'), io_number: nil)
    run(simple(words: [word('f')], redirects: [redirect]))
    expect(system.files['/f.txt'].string).to eq("body\n")
    expect(system.stdout.string).to be_empty
  end

  it 'dispatches to a defined function before falling through to an external' do
    state.functions.define('greet', Rush::AST::SimpleCommand.new([], [word('true')], []))
    expect(run(simple(words: [word('greet')]))).to be_success
  end

  it 'traces the command to stderr under xtrace' do
    state.options.set(:xtrace, true)
    run(simple(words: [word('true')]))
    expect(system.stderr.string).to eq("+ true\n")
  end
end
