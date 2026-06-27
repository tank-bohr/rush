# frozen_string_literal: true

RSpec.describe Rush::Builtins::Continue do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['continue', *args], io).call

  it 'raises a ContinueSignal with the default level of 1' do
    expect { run }.to raise_error(Rush::ContinueSignal) { |signal| expect(signal.count).to eq(1) }
  end

  it 'raises a ContinueSignal with the requested level' do
    expect { run('3') }.to raise_error(Rush::ContinueSignal) { |signal| expect(signal.count).to eq(3) }
  end

  it 'sets $? to success before unwinding (continue is a successful builtin)' do
    state.last_status = Rush::Status.new(1)
    expect { run }.to raise_error(Rush::ContinueSignal)
    expect(state.last_status).to be_success
  end
end
