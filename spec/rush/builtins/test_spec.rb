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

  it 'treats a lone ! or ( as an ordinary non-empty word' do
    expect(test('!')).to be_success
    expect(test('(')).to be_success
  end

  it 'reports a binary primary missing its right operand with exit status 2' do
    expect(test('x', '=').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("rush: test: =: argument expected\n")
  end

  it 'reports an unknown unary operator with exit status 2' do
    expect(test('-q', 'x').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("rush: test: x: unexpected operator\n")
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

  it 'evaluates the -p/-b/-c/-S file-type primaries via the port' do
    system.register('/fifo', type: :fifo)
    system.register('/blk', type: :block)
    system.register('/chr', type: :char)
    system.register('/sock', type: :socket)
    expect([test('-p', '/fifo'), test('-b', '/blk'), test('-c', '/chr'), test('-S', '/sock')]).to all(be_success)
    expect([test('-p', '/blk'), test('-b', '/fifo'), test('-c', '/sock'), test('-S', '/chr'),
            test('-p', '/none')]).to all(satisfy { |s| s.exitstatus == 1 })
  end

  it 'evaluates the -g/-u mode-bit primaries via the port' do
    system.register('/sgid', setgid: true)
    system.register('/suid', setuid: true)
    expect([test('-g', '/sgid'), test('-u', '/suid')]).to all(be_success)
    expect([test('-g', '/suid'), test('-u', '/sgid'), test('-g', '/none')])
      .to all(satisfy { |s| s.exitstatus == 1 })
  end

  it 'tests file-descriptor numbers with -t' do
    system.mark_tty(1)
    expect(test('-t', '1')).to be_success
    expect([test('-t', '0'), test('-t', '27'), test('-t', '-1')]).to all(satisfy { |s| s.exitstatus == 1 })
  end

  it 'accepts blank-padded and signed -t operands, like dash' do
    system.mark_tty(1)
    expect([test('-t', ' 1'), test('-t', '+1'), test('-t', '1 ')]).to all(be_success)
  end

  it 'rejects a non-numeric -t operand with exit status 2' do
    expect(test('-t', 'x').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("rush: test: Illegal number: x\n")
  end

  it 'treats a lone -t as the non-empty one-argument test' do
    expect(test('-t')).to be_success
  end

  it 'compares strings with = and !=' do
    expect([test('a', '=', 'a'), test('a', '!=', 'b')]).to all(be_success)
    expect([test('a', '=', 'b'), test('a', '!=', 'a')]).to all(satisfy { |s| !s.success? })
  end

  it 'compares integers with the six numeric primaries' do
    expect([test('3', '-eq', '3'), test('3', '-ne', '4'), test('5', '-gt', '4'),
            test('5', '-ge', '5'), test('4', '-lt', '5'), test('5', '-le', '5')]).to all(be_success)
    expect([test('3', '-eq', '4'), test('3', '-ne', '3'), test('4', '-gt', '5'),
            test('4', '-ge', '5'), test('5', '-lt', '4'), test('5', '-le', '4')])
      .to all(satisfy { |s| s.exitstatus == 1 })
  end

  it 'rejects a non-integer operand with exit status 2' do
    expect(test('x', '-eq', '1').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("rush: test: x: integer expected\n")
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

  it 'reports malformed binary-looking expressions with exit status 2' do
    expect(test('a', '=', 'a', 'extra').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("rush: test: extra: unexpected operator\n")
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

  it 'recurses through ( ) groupings of any length, like dash' do
    expect(test('(', 'a', '=', 'a', ')')).to be_success
    expect(test('(', 'a', '=', 'b', ')')).not_to be_success
    expect(test('(', '(', '-n', 'x', ')', ')')).to be_success
    expect(test('!', '(', 'a', '=', 'b', ')')).to be_success
    expect(test('(', '(', '(', 'a', ')', ')', ')')).to be_success
  end

  it 'treats an empty ( ) grouping as false rather than an error, like dash' do
    expect(test('(', ')').exitstatus).to eq(1)
    expect(test('(', '(', ')', ')').exitstatus).to eq(1)
  end

  it 'does not treat a trailing ) alone as a grouping' do
    expect(test(')')).to be_success
    expect(test('x', ')').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("rush: test: ): unexpected operator\n")
  end

  it 'reports more than four ungrouped arguments with exit status 2' do
    expect(test('a', 'b', 'c', 'd', 'e').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("rush: test: b: unexpected operator\n")
  end

  it 'evaluates the obsolescent -a/-o binary connectives' do
    expect([test('a', '=', 'a', '-a', 'b', '=', 'b'), test('a', '=', 'b', '-o', 'b', '=', 'b'),
            test('x', '-a', 'y'), test('x', '-o', '')]).to all(be_success)
    expect([test('a', '=', 'a', '-a', 'b', '=', 'c'), test('a', '=', 'b', '-o', 'b', '=', 'c'),
            test('x', '-a', ''), test('', '-o', '')]).to all(satisfy { |s| s.exitstatus == 1 })
  end

  it 'binds -a tighter than -o and lets \( \) regroup them, like dash' do
    expect(test('x', '-o', 'y', '-a', '')).to be_success
    expect(test('', '-a', 'y', '-o', 'z')).to be_success
    expect(test('(', 'x', '-o', '', ')', '-a', 'y')).to be_success
    expect(test('(', 'x', '-a', '', ')', '-o', '(', 'y', ')')).to be_success
  end

  it 'gives ! tighter binding than -a/-o inside long expressions, like dash' do
    expect(test('!', 'x', '-a', '!', 'y').exitstatus).to eq(1)
    expect(test('!', '', '-o', '!', '')).to be_success
    expect(test('x', '-a', '!', '')).to be_success
  end

  it 'peels a leading ! before a three-argument -a/-o reading, like dash' do
    expect(test('!', 'x', '-o', 'y').exitstatus).to eq(1)
    expect(test('!', '', '-a', 'y')).to be_success
  end

  it 'treats a missing arm after -a/-o as false rather than an error, like dash' do
    expect(test('x', '-o')).to be_success
    expect(test('x', '-a').exitstatus).to eq(1)
    expect(test('1', '-eq', '1', '-a').exitstatus).to eq(1)
  end

  it 'evaluates both arms of -a/-o, so a bad right arm still errors, like dash' do
    expect(test('x', '-o', 'y', '-eq', '3').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("rush: test: y: integer expected\n")
  end

  it 'keeps words that merely look like operators as operands' do
    expect(test('-t', '=', '-t')).to be_success
    expect(test('=', '-a', '=')).to be_success
    expect(test('-n', '-a')).to be_success
    expect(test('-z', '-a').exitstatus).to eq(1)
    expect(test('-e', '-a', '-e').exitstatus).to eq(2)
  end

  it 'negates four-argument tests honestly where dash mis-tracks parity (POSIX wins)' do
    expect(test('!', '!', '!', 'x').exitstatus).to eq(1) # dash answers 0 here
    expect(test('!', '!', '-n', 'x')).to be_success      # and 1 here
  end

  it 'requires and strips a closing ] in the [ form' do
    expect(bracket('x', ']')).to be_success
    expect(bracket(']')).not_to be_success
  end

  it 'reports a missing ] with exit status 2' do
    expect(bracket('x').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("rush: [: missing `]'\n")
  end
end
