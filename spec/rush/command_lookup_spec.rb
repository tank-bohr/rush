# frozen_string_literal: true

RSpec.describe Rush::CommandLookup do
  subject(:lookup) { described_class.new(executor) }

  let(:system) { FakeSystemCalls.new }
  let(:env) { Rush::Environment.new('PATH' => '/usr/bin') }
  let(:state) { Rush::ShellState.new(environment: env) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  it 'classifies keywords, special builtins and regular builtins' do
    expect(lookup.find('if')).to eq([:keyword, 'if'])
    expect(lookup.find('set')).to eq([:special, 'set'])
    expect(lookup.find('echo')).to eq([:builtin, 'echo'])
  end

  it 'classifies a defined function' do
    state.functions.define('f', Rush::AST::SimpleCommand.new([], [], []))
    expect(lookup.find('f')).to eq([:function, 'f'])
  end

  it 'finds an executable in PATH and a slash path directly' do
    system.register('/usr/bin/ls', executable: true)
    system.register('/opt/t', executable: true)
    expect([lookup.find('ls'), lookup.find('/opt/t')]).to eq([[:file, '/usr/bin/ls'], [:file, '/opt/t']])
  end

  it 'returns nil for an unknown name or a non-executable slash path' do
    expect([lookup.find('nope_zzz'), lookup.find('/no/such')]).to eq([nil, nil])
  end

  it 'searches an empty PATH element as the current directory' do
    env.assign('PATH', ':/usr/bin')
    system.register('tool', executable: true)
    expect(lookup.find('tool')).to eq([:file, 'tool'])
  end

  it 'classifies an alias, returning its value, outranking a function or builtin' do
    state.aliases.define('ll', 'ls -l')
    state.functions.define('ll', Rush::AST::SimpleCommand.new([], [], []))
    expect(lookup.find('ll')).to eq([:alias, 'ls -l'])
  end

  it 'lets a reserved word outrank an alias of the same name' do
    state.aliases.define('if', 'echo')
    expect(lookup.find('if')).to eq([:keyword, 'if'])
  end

  it 'describes an alias as "is an alias for value"' do
    state.aliases.define('ll', 'ls -l')
    expect(lookup.describe('ll')).to eq('ll is an alias for ls -l')
  end
end
