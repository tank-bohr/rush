# frozen_string_literal: true

RSpec.describe Rush::Builtins::Test do
  let(:system) { FakeSystemCalls.new }
  let(:executor) { Rush::Executor.new(system: system, state: Rush::ShellState.new) }
  let(:io) { Rush::IoTable.standard(system) }

  def test(*args)
    described_class.new(executor, ['test', *args], io).call
  end

  def bracket(*args)
    described_class.new(executor, ['[', *args], io).call
  end

  it 'is false with no arguments and tracks a single operand by emptiness' do
    expect(test).not_to be_success
    expect(test('x')).to be_success
    expect(test('')).not_to be_success
  end

  it 'evaluates the -n and -z unary primaries' do
    expect([test('-n', 'x'), test('-z', '')]).to all(be_success)
    expect([test('-n', ''), test('-z', 'x')]).to all(satisfy { |s| !s.success? })
  end

  it 'negates a one-argument test with !' do
    expect(test('!', '')).to be_success
    expect(test('!', 'x')).not_to be_success
  end

  it 'reports an unknown unary operator with exit status 2' do
    expect(test('-q', 'x').exitstatus).to eq(2)
    expect(system.stderr.string).to include('unary operator expected')
  end

  it 'evaluates -e/-f/-d against the filesystem' do
    system.register('/f', type: :file)
    system.register('/d', type: :dir)
    expect([test('-e', '/f'), test('-f', '/f'), test('-d', '/d')]).to all(be_success)
    expect([test('-e', '/none'), test('-f', '/d'), test('-d', '/f')]).to all(satisfy { |s| !s.success? })
  end

  it 'evaluates -r/-w/-x/-s/-h file primaries' do
    system.register('/f', readable: true, writable: false, executable: true, size: 0)
    system.register('/link', symlink: true)
    expect([test('-r', '/f'), test('-x', '/f'), test('-h', '/link'), test('-L', '/link')]).to all(be_success)
    expect([test('-w', '/f'), test('-s', '/f')]).to all(satisfy { |s| !s.success? })
  end

  it 'compares strings with = and !=' do
    expect([test('a', '=', 'a'), test('a', '!=', 'b')]).to all(be_success)
    expect([test('a', '=', 'b'), test('a', '!=', 'a')]).to all(satisfy { |s| !s.success? })
  end

  it 'compares integers with the six numeric primaries' do
    expect([test('3', '-eq', '3'), test('3', '-ne', '4'), test('5', '-gt', '4'),
            test('5', '-ge', '5'), test('4', '-lt', '5'), test('5', '-le', '5')]).to all(be_success)
  end

  it 'rejects a non-integer operand with exit status 2' do
    expect(test('x', '-eq', '1').exitstatus).to eq(2)
    expect(system.stderr.string).to include('integer expected')
  end

  it 'accepts integer operands padded with surrounding whitespace, as dash and bash do' do
    expect([test(' 5', '-eq', '5'), test('5 ', '-eq', '5'), test(' 5 ', '-eq', '5')]).to all(be_success)
  end

  it 'still rejects underscored or hexadecimal integer operands, as dash does' do
    expect([test('1_000', '-eq', '1000'), test('0x10', '-eq', '16')])
      .to all(satisfy { |s| s.exitstatus == 2 })
  end

  it 'handles three-argument ! and ( ) groupings' do
    expect(test('!', '-n', '')).to be_success
    expect(test('(', 'x', ')')).to be_success
    expect(test('(', '', ')')).not_to be_success
  end

  it 'reports malformed three-argument expressions with exit status 2' do
    expect(test('a', 'b', 'c').exitstatus).to eq(2)
    expect(test('(', 'x', 'y').exitstatus).to eq(2)
  end

  it 'handles four-argument ! and ( ) groupings' do
    expect(test('!', 'a', '=', 'b')).to be_success
    expect(test('!', 'a', '=', 'a')).not_to be_success
    expect(test('(', '-n', 'x', ')')).to be_success
  end

  it 'reports malformed four-argument expressions with exit status 2' do
    expect(test('a', 'b', 'c', 'd').exitstatus).to eq(2)
    expect(test('(', '-n', 'x', 'y').exitstatus).to eq(2)
  end

  it 'reports more than four arguments with exit status 2' do
    expect(test('a', 'b', 'c', 'd', 'e').exitstatus).to eq(2)
  end

  it 'requires and strips a closing ] in the [ form' do
    expect(bracket('x', ']')).to be_success
    expect(bracket(']')).not_to be_success
  end

  it 'reports a missing ] with exit status 2' do
    expect(bracket('x').exitstatus).to eq(2)
    expect(system.stderr.string).to include("missing `]'")
  end
end
