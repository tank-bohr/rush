# frozen_string_literal: true

RSpec.describe Rush::Executor do
  let(:system) { FakeSystemCalls.new }

  def state(vars = {})
    Rush::ShellState.new(environment: Rush::Environment.new(vars))
  end

  def build(state, **extra)
    described_class.new(system: system, state: state, **extra)
  end

  def word(text)
    Rush::AST::Word.literal(text)
  end

  def redirect(kind, target, io_number: nil)
    Rush::AST::Redirect.new(kind: kind, target: word(target), io_number: io_number)
  end

  def command(source)
    Rush::Parser.new(Rush::Lexer.new(source)).parse
  end

  it 'defaults the builtin registry and sets up the io table' do
    executor = build(state)
    expect(executor.builtins.key?('echo')).to be(true)
    expect(executor.io).to be_a(Rush::IoTable)
    expect(executor.instance_variable_get(:@errexit)).to be_a(Rush::ErrexitContext)
    expect(executor.instance_variable_get(:@redirect_scope)).to be_a(Rush::RedirectScope)
  end

  it 'backfills the logical pwd from the OS when the environment has none' do
    expect(build(state).state.variables.pwd).to eq('/home/test')
  end

  it 'keeps the environment PWD when present' do
    expect(build(state('PWD' => '/x')).state.variables.pwd).to eq('/x')
  end

  it 'records the last status when running a node and exposes the exit status' do
    target = state
    executor = build(target)
    executor.run(Rush::AST::SimpleCommand.new([], [word('false')], []))
    expect([target.last_status.exitstatus, executor.exitstatus]).to eq([1, 1])
  end

  it 'records launch success and $! when running a node asynchronously' do
    target = state
    executor = build(target)
    allow(system).to receive(:fork).and_return(4321)
    status = executor.run_async(Rush::AST::SimpleCommand.new([], [word('false')], []))
    expect([status.exitstatus, target.last_status.exitstatus, target.last_background_pid]).to eq([0, 0, 4321])
  end

  it 'records status 2 and carries on when a redirect duplicates an unopened fd' do
    target = state
    executor = build(target)
    expect(executor.run(command('echo x >&9')).exitstatus).to eq(2)
    expect(target.last_status.exitstatus).to eq(2)
  end

  it 'records status 2 when a node raises a redirect error directly' do
    target = state
    node_class = Class.new(Rush::AST::Node) do
      def execute(_executor)
        raise Rush::RedirectError, 'bad redirect'
      end
    end
    expect(build(target).run(node_class.new).exitstatus).to eq(2)
    expect(target.last_status.exitstatus).to eq(2)
  end

  it 'accepts an injected builtin registry' do
    registry = Rush::Builtins::Registry.new
    expect(build(state, builtins: registry).builtins).to be(registry)
  end

  it 'resets and records command-substitution status explicitly' do
    executor = build(state)
    executor.record_cmd_sub_status(Rush::Status.new(7))
    expect(executor.cmd_sub_status.exitstatus).to eq(7)
    executor.reset_cmd_sub_status
    expect(executor.cmd_sub_status).to be_success
  end

  it 'replaces the base io table' do
    executor = build(state)
    table = executor.io.with(1, StringIO.new)
    executor.replace_io(table)
    expect(executor.io).to be(table)
  end

  it 'runs an EXIT trap through the trap runner' do
    executor = build(state)
    executor.trap_runner.set(Rush::Signals::EXIT, 'exit 7')
    expect(executor.run_exit_trap(3)).to eq(7)
  end

  it 'passes the terminating status into a bare exit in the EXIT trap' do
    executor = build(state)
    executor.trap_runner.set(Rush::Signals::EXIT, 'exit')
    expect(executor.run_exit_trap(3)).to eq(3)
  end

  it 'resets caught traps and signal dispositions for a subshell' do
    target = state
    executor = build(target)
    executor.trap_runner.set(Rush::Signals::EXIT, 'echo exit')
    executor.trap_runner.set('TERM', 'echo term')
    executor.trap_runner.set('INT', '')
    executor.reset_caught_traps_for_subshell
    expect(target.traps.listing).to eq([['INT', '']])
    expect(system.traps_installed).to eq([['TERM', nil], %w[INT IGNORE], %w[TERM DEFAULT]])
  end

  it 'temporarily swaps io and restores it after success or failure' do
    executor = build(state)
    original = executor.io
    swapped = original.with(1, StringIO.new)
    expect(executor.with_io(swapped) { [executor.io, :result] }).to eq([swapped, :result])
    expect(executor.io).to be(original)
    expect { executor.with_io(swapped) { raise Rush::Error, 'boom' } }.to raise_error(Rush::Error, 'boom')
    expect(executor.io).to be(original)
  end

  it 'applies redirects, yields the redirected table, and closes opened streams' do
    executor = build(state)
    allow(system).to receive(:close_redirect).and_call_original
    status = executor.with_redirects([redirect(:out, '/file')]) do |io|
      expect(io.get(1)).to be(system.files.fetch('/file'))
      Rush::Status.success
    end
    expect(status).to be_success
    expect(system).to have_received(:close_redirect).with(system.files.fetch('/file'))
  end

  it 'closes an opened redirect stream overwritten by a later redirect' do
    executor = build(state)
    allow(system).to receive(:close_redirect).and_call_original
    redirects = [redirect(:out, '/lost'), redirect(:dup_out, '2', io_number: 1)]
    executor.with_redirects(redirects) { Rush::Status.success }
    expect(system).to have_received(:close_redirect).with(system.files.fetch('/lost'))
  end

  it 'uses the current io as the default redirect base' do
    executor = build(state)
    expect(executor.with_redirects([]) { |io| io }).to be(executor.io)
  end

  it 'does not close redirected streams that have become the executor base io' do
    executor = build(state)
    allow(system).to receive(:close_redirect).and_call_original
    executor.with_redirects([redirect(:out, '/persist')]) { |io| executor.replace_io(io) }
    expect(executor.io.get(1)).to be(system.files.fetch('/persist'))
    expect(system).not_to have_received(:close_redirect)
  end

  it 'closes exec redirect streams that are overwritten before being committed' do
    executor = build(state)
    allow(system).to receive(:close_redirect).and_call_original
    redirects = [redirect(:out, '/lost'), redirect(:dup_out, '2', io_number: 1)]
    executor.with_redirects(redirects) { |io| executor.replace_io(io) }
    expect(executor.io.get(1)).to be(system.stderr)
    expect(system).to have_received(:close_redirect).with(system.files.fetch('/lost'))
  end

  it 'runs a redirected compound command with temporary io' do
    executor = build(state)
    status = executor.run_redirected(Rush::AST::SimpleCommand.new([], [word('echo'), word('body')], []),
                                     [redirect(:out, '/compound')])
    expect([status.exitstatus, system.files.fetch('/compound').string, system.stdout.string])
      .to eq([0, "body\n", ''])
  end

  it 'expands redirect targets through the executor expander' do
    target = state('name' => 'expanded')
    executor = build(target)
    word = Rush::AST::Word.new([
                                 Rush::AST::LiteralSegment.new('/', false),
                                 Rush::AST::ParamSegment.new(Rush::AST::ParamRef.simple('name'), false)
                               ])
    executor.with_redirects([Rush::AST::Redirect.new(kind: :out, target: word, io_number: nil)]) do
      Rush::Status.success
    end
    expect(system.files).to have_key('/expanded')
  end

  describe '#exit_on_error' do
    let(:fail_status) { Rush::Status.failure }

    def errexit(target)
      target.tap { |s| s.options.set(:errexit, true) }
    end

    it 'returns the status unchanged when errexit is off' do
      executor = build(state)
      expect(executor.exit_on_error(fail_status)).to be(fail_status)
    end

    it 'reports condition success in a tested context' do
      executor = build(errexit(state))
      expect([executor.succeeds?(command('true')), executor.succeeds?(command('false'))]).to eq([true, false])
      expect { executor.exit_on_error(fail_status) }.to raise_error(Rush::ExitSignal)
    end

    it 'returns block values and restores tested state after exceptions' do
      executor = build(errexit(state))
      expect(executor.tested { :tested }).to eq(:tested)
      expect(executor.untested { :untested }).to eq(:untested)
      expect { executor.tested { raise Rush::Error, 'boom' } }.to raise_error(Rush::Error, 'boom')
      expect { executor.exit_on_error(fail_status) }.to raise_error(Rush::ExitSignal)
    end

    it 'restores a surrounding tested context after an untested block' do
      executor = build(errexit(state))
      executor.tested do
        expect { executor.untested { executor.exit_on_error(fail_status) } }.to raise_error(Rush::ExitSignal)
        expect(executor.exit_on_error(fail_status)).to be(fail_status)
      end
    end

    it 'aborts with the failed status when errexit is on outside a tested context' do
      expect { build(errexit(state)).exit_on_error(Rush::Status.new(4)) }
        .to raise_error(Rush::ExitSignal) { |e| expect(e.code).to eq(4) }
    end

    it 'does not abort on a successful command under errexit' do
      expect(build(errexit(state)).exit_on_error(Rush::Status.success)).to be_success
    end

    it 'suppresses the abort inside a tested context' do
      executor = build(errexit(state))
      expect(executor.tested { executor.exit_on_error(fail_status) }).to be(fail_status)
    end

    it 'restores errexit checking after an untested (fresh) context' do
      executor = build(errexit(state))
      executor.tested { executor.untested { nil } }
      expect { executor.exit_on_error(fail_status) }.to raise_error(Rush::ExitSignal)
    end
  end
end
