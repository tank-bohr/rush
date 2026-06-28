# frozen_string_literal: true

RSpec.describe Rush::Builtins::Readonly do
  let(:system) { FakeSystemCalls.new }
  let(:env) { Rush::Environment.new({}) }
  let(:state) { Rush::ShellState.new(environment: env) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['readonly', *args], io).call
  end

  it 'assigns and marks a name read only' do
    expect(run('X=1')).to be_success
    expect(env.get('X')).to eq('1')
    expect { env.assign('X', '2') }.to raise_error(Rush::ReadonlyError)
  end

  it 'marks an existing variable read only without a value' do
    env.assign('Y', 'v')
    run('Y')
    expect { env.assign('Y', 'z') }.to raise_error(Rush::ReadonlyError)
  end
end
