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

  it 'uses the current IFS and strips the line terminator before splitting' do
    env.assign('IFS', ':')
    status, = read("x:y:z\n", 'a', 'b')
    expect(status).to be_success
    expect([env.get('a'), env.get('b')]).to eq(['x', 'y:z'])
  end

  it 'processes backslash escapes by default and keeps them with -r' do
    read("a\\tb\\nc\n", 'cooked')
    read("a\\tb\n", '-r', 'rawvar')
    expect([env.get('cooked'), env.get('rawvar')]).to eq(['atbnc', 'a\\tb'])
  end

  it 'continues onto the next physical line after a trailing unescaped backslash' do
    status, = read("a\\\nb\n", 'joined')
    expect(status).to be_success
    expect(env.get('joined')).to eq('ab')
  end

  it 'assigns what was read but fails when a continuation hits end of file' do
    status, = read("a\\\n", 'cooked')
    expect(status).not_to be_success
    expect(env.get('cooked')).to eq('a')
  end

  it 'assigns a final line without a newline terminator but reports failure' do
    status, = read('abc', 'partial')
    expect(status).not_to be_success
    expect(env.get('partial')).to eq('abc')
  end

  it 'shields an escaped space from field splitting' do
    status, = read("a\\ b c\n", 'first', 'rest')
    expect(status).to be_success
    expect([env.get('first'), env.get('rest')]).to eq(['a b', 'c'])
  end

  it 'errors with exit status 2 when given no variable' do
    status, system = read("hi\n")
    expect(status.exitstatus).to eq(2)
    expect(system.stderr.string).to eq("rush: read: arg count\n")
  end
end
