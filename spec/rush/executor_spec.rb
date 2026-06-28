# frozen_string_literal: true

RSpec.describe Rush::Executor do
  let(:system) { FakeSystemCalls.new }

  def state(vars = {}) = Rush::ShellState.new(environment: Rush::Environment.new(vars))
  def build(state, **extra) = described_class.new(system: system, state: state, **extra)

  it 'defaults the builtin registry and sets up the io table' do
    executor = build(state)
    expect(executor.builtins.key?('echo')).to be(true)
    expect(executor.io).to be_a(Rush::IoTable)
  end

  it 'backfills the logical pwd from the OS when the environment has none' do
    expect(build(state).state.scope.pwd).to eq('/home/test')
  end

  it 'keeps the environment PWD when present' do
    expect(build(state('PWD' => '/x')).state.scope.pwd).to eq('/x')
  end

  it 'records the last status when running a node' do
    target = state
    build(target).run(Rush::AST::SimpleCommand.new([], [Rush::AST::Word.literal('false')], []))
    expect(target.last_status.exitstatus).to eq(1)
  end

  it 'records status 2 and carries on when a redirect duplicates an unopened fd' do
    target = state
    build(target).run(Rush::Parser.new(Rush::Lexer.new('echo x >&9')).parse)
    expect(target.last_status.exitstatus).to eq(2)
  end

  it 'accepts an injected builtin registry' do
    registry = Rush::Builtins::Registry.new
    expect(build(state, builtins: registry).builtins).to be(registry)
  end

  describe '#exit_on_error' do
    let(:fail_status) { Rush::Status.failure }

    def errexit(target) = target.tap { |s| s.options.set(:errexit, true) }

    it 'returns the status unchanged when errexit is off' do
      expect(build(state).exit_on_error(fail_status)).to be(fail_status)
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
