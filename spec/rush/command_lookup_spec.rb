# frozen_string_literal: true

RSpec.describe Rush::CommandLookup do
  subject(:lookup) { described_class.new(executor) }

  let(:system) { FakeSystemCalls.new }
  let(:env) { Rush::Environment.new('PATH' => '/usr/bin') }
  let(:state) { Rush::ShellState.new(environment: env) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  it 'classifies keywords, special builtins and regular builtins' do
    expect([lookup.describe('if'), lookup.describe('set'), lookup.describe('echo')])
      .to eq(['if is a shell keyword', 'set is a special shell builtin', 'echo is a shell builtin'])
  end

  it 'classifies a defined function' do
    state.functions.define('f', Rush::AST::SimpleCommand.new([], [], []))
    expect(lookup.describe('f')).to eq('f is a shell function')
  end

  it 'finds an executable in PATH and a slash path directly' do
    system.register('/usr/bin/ls', executable: true)
    system.register('/opt/t', executable: true)
    expect([lookup.describe('ls'), lookup.describe('/opt/t')]).to eq(['ls is /usr/bin/ls', '/opt/t is /opt/t'])
  end

  it 'reports an unknown name or a non-executable slash path as not known' do
    expect([lookup.find('nope_zzz').known?, lookup.find('/no/such').known?]).to eq([false, false])
    expect(lookup.describe('nope_zzz')).to be_nil
  end

  it 'searches an empty PATH element as the current directory' do
    env.assign('PATH', ':/usr/bin')
    system.register('tool', executable: true)
    expect(lookup.describe('tool')).to eq('tool is tool')
  end

  it 'classifies an alias, returning its value, outranking a function or builtin' do
    state.aliases.define('ll', 'ls -l')
    state.functions.define('ll', Rush::AST::SimpleCommand.new([], [], []))
    expect(lookup.describe('ll')).to eq('ll is an alias for ls -l')
  end

  it 'lets a reserved word outrank an alias of the same name' do
    state.aliases.define('if', 'echo')
    expect(lookup.describe('if')).to eq('if is a shell keyword')
  end
end
