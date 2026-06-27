# frozen_string_literal: true

RSpec.describe Rush::Builtins::Break do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['break', *args], io).call

  it 'raises a BreakSignal with the default level of 1' do
    expect { run }.to raise_error(Rush::BreakSignal) { |signal| expect(signal.count).to eq(1) }
  end

  it 'raises a BreakSignal with the requested level' do
    expect { run('2') }.to raise_error(Rush::BreakSignal) { |signal| expect(signal.count).to eq(2) }
  end

  it 'sets $? to success before unwinding (break is a successful builtin)' do
    state.last_status = Rush::Status.new(1)
    expect { run }.to raise_error(Rush::BreakSignal)
    expect(state.last_status).to be_success
  end
end
