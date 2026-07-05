# frozen_string_literal: true

RSpec.describe Rush::Builtins::Colon do
  let(:system) { FakeSystemCalls.new }
  let(:executor) { Rush::Executor.new(system: system, state: Rush::ShellState.new) }
  let(:io) { Rush::IoTable.standard(system) }

  it 'succeeds without writing output' do
    status = described_class.new(executor, [':', 'ignored'], io).call

    expect(status).to be_success
    expect([system.stdout.string, system.stderr.string]).to eq(['', ''])
  end
end
