# frozen_string_literal: true

RSpec.describe Rush::Builtins::Export do
  let(:system) { FakeSystemCalls.new }
  let(:env) { Rush::Environment.new({}) }
  let(:state) { Rush::ShellState.new(environment: env) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['export', *args], io).call

  it 'assigns and marks a name for export' do
    expect(run('X=1')).to be_success
    expect(env.get('X')).to eq('1')
    expect(env.exported).to include('X' => '1')
  end

  it 'marks an existing variable for export without a value' do
    env.assign('Y', 'v')
    run('Y')
    expect(env.exported).to include('Y' => 'v')
  end
end
