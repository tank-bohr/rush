# frozen_string_literal: true

RSpec.describe Rush::Builtins::True do
  let(:system) { FakeSystemCalls.new }
  let(:executor) { Rush::Executor.new(system: system, state: Rush::ShellState.new) }
  let(:io) { Rush::IoTable.standard(system) }

  it 'succeeds without writing output' do
    status = described_class.new(executor, ['true'], io).call

    expect(status).to be_success
    expect([system.stdout.string, system.stderr.string]).to eq(['', ''])
  end
end
