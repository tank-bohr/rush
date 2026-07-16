# frozen_string_literal: true

RSpec.describe Rush::Builtins::Command do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new('PATH' => '/usr/bin')) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['command', *args], io).call
  end

  it 'prints the name for -v of a builtin and the path for an external' do
    system.register('/usr/bin/ls', executable: true)
    expect(run('-v', 'echo')).to be_success
    expect(run('-v', 'ls')).to be_success
    expect(system.stdout.string).to eq("echo\n/usr/bin/ls\n")
  end

  it 'fails with 127 for -v of an unknown name but exits 0 quietly with no operand (dash-probed)' do
    expect([run('-v', 'nope_zzz').exitstatus, run('-v').exitstatus]).to eq([127, 0])
    expect(system.stdout.string).to be_empty
  end

  it 'runs bare command with no operands as the colon no-op (dash-probed)' do
    expect(run).to be_success
    expect(system.stdout.string).to be_empty
  end

  it 'describes a name verbosely with -V like type does' do
    expect(run('-V', 'echo')).to be_success
    expect(system.stdout.string).to eq("echo is a shell builtin\n")
  end

  it 'reports not found for -V of an unknown name with 127 but exits 0 with no operand (dash-probed)' do
    expect(run('-V', 'nope_zzz').exitstatus).to eq(127)
    expect(run('-V').exitstatus).to eq(0)
    expect(system.stdout.string).to eq("nope_zzz: not found\n")
  end

  # dash resolves -p against its compiled-in default path; POSIX.1-2017 says
  # the default PATH is the confstr _CS_PATH value, so rush pins the standard:
  # the port's default_path (the fake answers /default/bin) wins over $PATH.
  it 'searches the default PATH for -v under -p, whatever the cluster shape' do
    system.register('/usr/bin/ls', executable: true)
    system.register('/default/bin/ls', executable: true)
    expect([run('-p', '-v', 'ls'), run('-pv', 'ls'), run('-vp', 'ls')]).to all(be_success)
    expect(system.stdout.string).to eq("/default/bin/ls\n" * 3)
  end

  it 'still reports functions and builtins under -p -v (dash-probed: -p only moves the file search)' do
    state.functions.define('f', Rush::AST::SimpleCommand.from_groups([], [], []))
    expect([run('-pv', 'f'), run('-pv', 'echo')]).to all(be_success)
    expect(system.stdout.string).to eq("f\necho\n")
  end

  it 'describes verbosely under -pV, and -V outranks -v in either order (dash-probed)' do
    run('-pV', 'echo')
    run('-v', '-V', 'echo')
    run('-V', '-v', 'echo')
    expect(system.stdout.string).to eq("echo is a shell builtin\n" * 3)
  end

  it 'runs a builtin under -p regardless of the default path' do
    expect(run('-p', 'echo', 'hi')).to be_success
    expect(system.stdout.string).to eq("hi\n")
  end

  it 'executes an external resolved on the default PATH under -p, keeping its name as argv[0]' do
    system.register('/default/bin/prog', executable: true)
    external = instance_double(Rush::External, call_file: Rush::Status.success)
    allow(Rush::External).to receive(:new).and_return(external)
    expect(run('-p', 'prog', 'a')).to be_success
    expect(Rush::External).to have_received(:new).with(executor, %w[prog a], io, kind_of(Hash))
    expect(external).to have_received(:call_file).with('/default/bin/prog')
  end

  it 'fails with 127 under -p when the command lives only on $PATH, not the default one' do
    system.register('/usr/bin/onlyhere', executable: true)
    expect(run('-p', 'onlyhere').exitstatus).to eq(127)
    expect(system.stderr.string).to eq("rush: onlyhere: not found\n")
  end

  it 'rejects an unknown option letter with status 2, like dash' do
    expect([run('-z', 'echo').exitstatus, run('-pz', 'echo').exitstatus]).to eq([2, 2])
    expect(system.stderr.string).to eq("rush: command: Illegal option -z\n" * 2)
  end

  it 'stops option parsing at --, treating what follows as the command' do
    expect(run('--', 'echo', 'hi')).to be_success
    expect(system.stdout.string).to eq("hi\n")
  end

  it 'runs a builtin, bypassing a shadowing function' do
    state.functions.define('echo', Rush::AST::SimpleCommand.from_groups([], [], []))
    run('echo', 'hi')
    expect(system.stdout.string).to eq("hi\n")
  end

  it 'demotes special-builtin errors to ordinary status 2 failures' do
    state.variables.assign('X', 'fixed')
    state.variables.readonly('X')

    statuses = [run('shift', '5'), run('.', '/missing'), run('eval', 'echo ${MISSING?bad}'),
                run('export', 'X=changed')]
    expect(statuses.map(&:exitstatus)).to eq([2, 2, 2, 2])
    expect(system.stderr.string.lines.size).to eq(4)
  end

  it 'still propagates the target builtin control flow' do
    expect { run('return', '7') }.to raise_error(Rush::ReturnSignal) { |error| expect(error.code).to eq(7) }
  end

  it 'constructs a builtin with the current executor' do
    registry = Rush::Builtins::Registry.new
    checker = Class.new(Rush::Builtins::Base) do
      def call
        executor.state.record_status(success)
        success
      end
    end
    registry.register('check-executor', checker)
    custom = Rush::Executor.new(system: system, state: state, builtins: registry)

    status = described_class.new(custom, %w[command check-executor], io).call
    expect(status).to be_success
  end

  it 'runs an external command, bypassing functions' do
    external = instance_double(Rush::External, call: Rush::Status.success)
    allow(Rush::External).to receive(:new).and_return(external)
    expect(run('extprog', 'arg')).to be_success
    expect(Rush::External).to have_received(:new).with(executor, %w[extprog arg], io, kind_of(Hash))
  end

  it 'returns success when given no name to run' do
    colon = instance_double(Rush::Builtins::Colon, call: Rush::Status.success)
    allow(Rush::Builtins::Colon).to receive(:new).with(executor, [], io).and_return(colon)

    expect(run).to be_success
    expect(Rush::Builtins::Colon).to have_received(:new).with(executor, [], io)
  end

  it "prints an alias as alias 'name=value' for -v" do
    state.aliases.define('ll', 'ls -l')
    run('-v', 'll')
    expect(system.stdout.string).to eq("alias 'll=ls -l'\n")
  end

  it 'describes an alias verbosely with -V' do
    state.aliases.define('ll', 'ls -l')
    run('-V', 'll')
    expect(system.stdout.string).to eq("ll is an alias for ls -l\n")
  end
end
