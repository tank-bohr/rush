# frozen_string_literal: true

RSpec.describe Rush::Builtins::Read do
  let(:env) { Rush::Environment.new({}) }
  let(:state) { Rush::ShellState.new(environment: env) }

  def read(input, *args)
    system = FakeSystemCalls.new(stdin: input)
    executor = Rush::Executor.new(system: system, state: state)
    [described_class.new(executor, ['read', *args], Rush::IoTable.standard(system)).call, system]
  end

  it 'reads fields into variables, the remainder to the last' do
    status, = read("x y z w\n", 'a', 'b', 'c')
    expect(status).to be_success
    expect([env.get('a'), env.get('b'), env.get('c')]).to eq(['x', 'y', 'z w'])
  end

  it 'clears extra variables and returns failure at end of file' do
    status, = read('', 'a', 'b')
    expect(status).not_to be_success
    expect([env.get('a'), env.get('b')]).to eq(['', ''])
  end

  it 'processes backslash escapes by default and keeps them with -r' do
    read("a\\tb\n", 'cooked')
    read("a\\tb\n", '-r', 'rawvar')
    expect([env.get('cooked'), env.get('rawvar')]).to eq(['atb', 'a\\tb'])
  end

  it 'errors with exit status 2 when given no variable' do
    status, system = read("hi\n")
    expect(status.exitstatus).to eq(2)
    expect(system.stderr.string).to include('arg count')
  end
end
