# frozen_string_literal: true

RSpec.describe Rush::Builtins::Pwd do
  it 'prints the logical working directory' do
    system = FakeSystemCalls.new
    state = Rush::ShellState.new
    state.pwd = '/work'
    executor = Rush::Executor.new(system: system, state: state)
    described_class.new(executor, ['pwd'], Rush::IoTable.standard(system)).call
    expect(system.stdout.string).to eq("/work\n")
  end
end
