# frozen_string_literal: true

RSpec.describe Rush::BackgroundRunner do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def node(status = Rush::Status.success)
    klass = Class.new(Rush::AST::Node) do
      define_method(:execute) { |_executor| status }
    end
    klass.new
  end

  it 'records the background pid and returns launch success without waiting' do
    allow(system).to receive(:fork).and_return(1234)
    allow(system).to receive(:waitpid2).and_call_original

    status = described_class.new(executor, node(Rush::Status.new(7))).call

    expect(status).to be_success
    expect(state.last_background_pid).to eq(1234)
    expect(system).not_to have_received(:waitpid2)
  end

  it 'runs the body with subshell error semantics' do
    expect(described_class.new(executor, node(Rush::Status.new(5))).run_body.exitstatus).to eq(5)
  end

  it 'rebinds the child stdin to /dev/null before the body runs (POSIX 2.9.3.1)' do
    seen = nil
    capture = Class.new(Rush::AST::Node) do
      define_method(:execute) do |ex|
        seen = ex.io.get(0)
        Rush::Status.success
      end
    end
    described_class.new(executor, capture.new).run_body
    expect(seen).to be(system.files[File::NULL])
  end

  it 'starts the child with SIGINT and SIGQUIT ignored (POSIX 2.11)' do
    described_class.new(executor, node).run_body
    expect(system.traps_installed).to include(%w[INT IGNORE], %w[QUIT IGNORE])
  end

  it 'installs the ignores after the subshell trap reset, so interactive bases cannot undo them' do
    Rush::InteractiveSignals.install(executor)
    described_class.new(executor, node).run_body
    expect(system.traps_installed.rfind { |name, _command| name == 'INT' }).to eq(%w[INT IGNORE])
  end

  def parsed(source)
    Rush::Parser.new(Rush::Lexer.new(source)).parse
  end

  context 'when job control (set -m) is on' do
    before { executor.job_control.enable(system.stderr) }

    it 'places the job in its own process group (parent side of the double setpgid)' do
      allow(system).to receive(:fork).and_return(1234)
      described_class.new(executor, parsed('sleep 99')).call
      expect(system.pgids_set).to eq([[1234, 0]])
    end

    it 'stamps the recorded entry with the rendered command text (dash keeps text under -m)' do
      allow(system).to receive(:fork).and_return(1234)
      described_class.new(executor, parsed('sleep $T | cat')).call
      expect(executor.jobs.current.text).to eq('sleep ${T} | cat')
    end

    it 'leaves the child stdin alone — the job sits in its own group (dash-probed)' do
      seen = nil
      capture = Class.new(Rush::AST::Node) do
        define_method(:execute) do |ex|
          seen = ex.io.get(0)
          Rush::Status.success
        end
      end
      described_class.new(executor, capture.new).run_body
      expect(seen).to be(system.stdin)
    end

    it 'leaves SIGINT and SIGQUIT at their defaults (POSIX 2.11 applies only without job control)' do
      described_class.new(executor, node).run_body
      expect(system.traps_installed).not_to include(%w[INT IGNORE], %w[QUIT IGNORE])
    end

    it 'never hands the terminal to a background job (dash-probed: the tty stays with the shell)' do
      tty_system = FakeSystemCalls.new(tty: true)
      tty_executor = Rush::Executor.new(system: tty_system, state: Rush::ShellState.new)
      tty_executor.job_control.enable(tty_system.stderr)
      allow(tty_system).to receive(:fork).and_return(1234)
      described_class.new(tty_executor, parsed('sleep 99')).call
      expect(tty_system.tty_leaders).to be_empty
      expect(tty_system.handovers).to eq([4242])
    end
  end
end
