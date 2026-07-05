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
end
