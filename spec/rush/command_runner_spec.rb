# frozen_string_literal: true

RSpec.describe Rush::CommandRunner do
  let(:system) { FakeSystemCalls.new }
  let(:env) { Rush::Environment.new({}) }
  let(:state) { Rush::ShellState.new(environment: env) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def word(text)
    Rush::AST::Word.literal(text)
  end

  def assignment(name, text)
    Rush::AST::Assignment.new(name: name, value: word(text))
  end

  def simple(assignments: [], words: [], redirects: [])
    Rush::AST::SimpleCommand.new(assignments, words, redirects)
  end

  def run(command)
    described_class.new(executor, command).call
  end

  def program(source)
    Rush::Parser.new(Rush::Lexer.new(source)).parse
  end

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

  it 'persists prefix assignments on a direct special builtin without exporting new names' do
    command = simple(assignments: [assignment('X', '1')], words: [word(':')])

    expect(run(command)).to be_success
    expect([env.get('X'), state.variables.exported]).to eq(['1', {}])
  end

  it 'persists the assignments before a direct special-builtin error' do
    command = simple(assignments: [assignment('X', '1')], words: [word('shift'), word('5')])

    expect { run(command) }.to raise_error(Rush::BuiltinError)
    expect(env.get('X')).to eq('1')
  end

  it 'keeps command-demoted special-builtin prefix assignments temporary' do
    command = simple(assignments: [assignment('X', '1')], words: [word('command'), word(':')])

    expect(run(command)).to be_success
    expect(env.get('X')).to be_nil
  end

  it 'dispatches to an external when no builtin matches, exporting prefix assignments' do
    captured = nil
    external = instance_double(Rush::External, call: Rush::Status.success)
    allow(Rush::External).to receive(:new) { |*args| captured = args }.and_return(external)
    status = run(simple(assignments: [assignment('X', '1')], words: [word('ls')]))
    expect(status).to be_success
    expect(external).to have_received(:call)
    expect(captured).to match([executor, ['ls'], executor.io, hash_including('X' => '1')])
  end

  it 'rejects a readonly prefix before dispatching an external' do
    env.assign('X', 'locked')
    env.readonly('X')
    allow(Rush::External).to receive(:new)
    command = simple(assignments: [assignment('X', 'new')], words: [word('ls')])

    expect { run(command) }.to raise_error(Rush::ReadonlyError)
    expect(Rush::External).not_to have_received(:new)
  end

  it 'forwards prefix assignments through command to its nested external' do
    captured = nil
    external = instance_double(Rush::External, call: Rush::Status.success)
    allow(Rush::External).to receive(:new) { |*args| captured = args }.and_return(external)
    command = simple(assignments: [assignment('X', 'inner')], words: [word('command'), word('show-env')])

    expect(run(command)).to be_success
    expect(captured).to match([executor, %w[show-env], executor.io, hash_including('X' => 'inner')])
    expect(env.get('X')).to be_nil
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

  it 'applies redirects for a bare assignment command' do
    allow(system).to receive(:open_file).and_raise(Errno::EACCES)
    redirect = Rush::AST::Redirect.new(kind: :out, target: word('/denied'), io_number: nil)
    expect { run(simple(assignments: [assignment('X', '1')], redirects: [redirect])) }.to raise_error(Rush::RedirectError)
    expect(env.get('X')).to be_nil
  end

  it 'escalates a redirect-open failure on a special builtin to a fatal builtin error' do
    allow(system).to receive(:open_file).and_raise(Errno::ENOENT)
    redirect = Rush::AST::Redirect.new(kind: :out, target: word('/denied'), io_number: nil)
    expect { run(simple(words: [word(':')], redirects: [redirect])) }
      .to raise_error(Rush::BuiltinError, '/denied: cannot redirect')
  end

  it 'fails with status 1 when a builtin writes to a fd closed by >&-' do
    redirect = Rush::AST::Redirect.new(kind: :dup_out, target: word('-'), io_number: nil)
    expect(run(simple(words: [word('echo'), word('hi')], redirects: [redirect])).exitstatus).to eq(1)
  end

  it 'commits redirect-only exec and leaves its opened file open so it persists' do
    allow(system).to receive(:close_redirect)
    redirect = Rush::AST::Redirect.new(kind: :out, target: word('/f'), io_number: nil)
    run(simple(words: [word('exec')], redirects: [redirect]))
    expect(executor.io.get(1)).to be(system.files.fetch('/f'))
    expect(system).not_to have_received(:close_redirect)
  end

  it 'binds a redirect on a function call to the function body' do
    state.functions.define('f', Rush::AST::SimpleCommand.new([], [word('echo'), word('body')], []))
    redirect = Rush::AST::Redirect.new(kind: :out, target: word('/f.txt'), io_number: nil)
    run(simple(words: [word('f')], redirects: [redirect]))
    expect(system.files.fetch('/f.txt').string).to eq("body\n")
    expect(system.stdout.string).to be_empty
  end

  it 'passes only function arguments as positional parameters' do
    state.functions.define('show', program('echo "$1:$2"'))
    run(simple(words: [word('show'), word('one'), word('two')]))
    expect(system.stdout.string).to eq("one:two\n")
  end

  it 'scopes prefix assignments around a function while keeping unrelated writes' do
    env.assign('X', 'outer')
    env.assign('BASE', 'old')
    env.export('BASE')
    state.functions.define('f', program('SEEN=$X; X=body; Y=live; BASE=changed'))
    command = simple(assignments: [assignment('X', 'temporary')], words: [word('f')])

    expect(run(command)).to be_success
    expect([env.get('X'), env.get('SEEN'), env.get('Y'), env.get('BASE')])
      .to eq(%w[outer temporary live changed])
  end

  it 'lets an exec redirection inside an unredirected function persist' do
    state.functions.define('f', program('exec > /from-function'))
    run(simple(words: [word('f')]))
    expect(executor.io.get(1)).to be(system.files.fetch('/from-function'))
  end

  it 'dispatches to a defined function before falling through to an external' do
    state.functions.define('greet', Rush::AST::SimpleCommand.new([], [word('true')], []))
    expect(run(simple(words: [word('greet')]))).to be_success
  end

  it 'lets a special builtin outrank a function of the same name' do
    state.functions.define(':', program('echo function'))
    expect(run(simple(words: [word(':')]))).to be_success
    expect(system.stdout.string).to be_empty
  end

  it 'falls back to PATH for a special-builtin name missing from the registry' do
    registry = Rush::Builtins::Registry.new
    runner = described_class.new(Rush::Executor.new(system: system, state: state, builtins: registry),
                                 simple(words: [word(':')]))
    external = instance_double(Rush::External, call: Rush::Status.success)
    allow(Rush::External).to receive(:new).and_return(external)
    expect(runner.call).to be_success
    expect(Rush::External).to have_received(:new)
  end

  it 'uses the provided base io for a command without redirects' do
    out = StringIO.new
    base_io = executor.io.with(1, out)
    described_class.new(executor, simple(words: [word('echo'), word('hi')]), base_io).call
    expect([out.string, system.stdout.string]).to eq(["hi\n", ''])
  end

  it 'uses the provided base io while applying bare redirects' do
    base_io = Rush::IoTable.new({})
    redirect = Rush::AST::Redirect.new(kind: :dup_out, target: word('2'), io_number: nil)
    runner = described_class.new(executor, simple(assignments: [assignment('X', '1')], redirects: [redirect]), base_io)
    expect { runner.call }.to raise_error(Rush::RedirectError, '2: fd not open')
  end

  it 'does not trace commands unless xtrace is enabled' do
    run(simple(words: [word('true')]))
    expect(system.stderr.string).to be_empty
  end

  it 'traces the command to stderr under xtrace' do
    state.options.set(:xtrace, true)
    run(simple(words: [word('echo'), word('hello'), word('world')]))
    expect(system.stderr.string).to eq("+ echo hello world\n")
  end

  it 'prefixes the trace with the expanded PS4' do
    state.options.set(:xtrace, true)
    state.variables.assign('n', '2')
    state.variables.assign('PS4', '[$n] ')
    run(simple(words: [word('echo'), word('hi')]))
    expect(system.stderr.string).to eq("[2] echo hi\n")
  end

  it 're-reads PS4 for every trace line' do
    state.options.set(:xtrace, true)
    run(simple(words: [word('true')]))
    state.variables.assign('PS4', '# ')
    run(simple(words: [word('true')]))
    expect(system.stderr.string).to eq("+ true\n# true\n")
  end
end
