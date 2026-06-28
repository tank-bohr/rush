# frozen_string_literal: true

RSpec.describe Rush::Builtins::Printf do
  let(:system) { FakeSystemCalls.new }
  let(:executor) { Rush::Executor.new(system: system, state: Rush::ShellState.new) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['printf', *args], io).call
  end

  it 'writes the formatted text without a trailing newline of its own' do
    expect(run('%s-%s', 'a', 'b')).to be_success
    expect(system.stdout.string).to eq('a-b')
  end

  it 'returns failure and reports a non-numeric argument' do
    expect(run('%d', 'oops')).not_to be_success
    expect(system.stderr.string).to include('numeric')
  end

  it 'errors with exit status 2 when given no format' do
    expect(run.exitstatus).to eq(2)
    expect(system.stderr.string).to include('usage')
  end
end
