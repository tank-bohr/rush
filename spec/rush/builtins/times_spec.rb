# frozen_string_literal: true

RSpec.describe Rush::Builtins::Times do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run = described_class.new(executor, ['times'], io).call

  it 'writes the shell and child CPU times, two lines, formatted like dash' do
    expect(run).to be_success
    expect(system.stdout.string).to eq("0m0.000000s 0m0.000000s\n0m0.000000s 0m0.000000s\n")
  end

  it 'splits seconds into whole minutes and a six-decimal remainder' do
    allow(system).to receive(:times).and_return(FakeSystemCalls::ProcessTimes.new(75.5, 0.0, 0.0, 0.0))
    run
    expect(system.stdout.string.lines.first).to eq("1m15.500000s 0m0.000000s\n")
  end
end
