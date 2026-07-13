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
    expect([lookup.find('if').terse, lookup.find('set').terse, lookup.find('echo').terse]).to eq(%w[if set echo])
  end

  it 'classifies a defined function' do
    state.functions.define('f', Rush::AST::SimpleCommand.new([], [], []))
    expect(lookup.describe('f')).to eq('f is a shell function')
  end

  it 'does not label an unavailable special builtin and continues to the PATH resolver' do
    system.register('/usr/bin/:', executable: true)
    empty = Rush::Builtins::Registry.new
    custom = Rush::Executor.new(system: system, state: state, builtins: empty)

    expect(described_class.new(custom).describe(':')).to eq(': is /usr/bin/:')
  end

  it 'finds an executable in PATH and a slash path directly' do
    system.register('/usr/bin/ls', executable: true)
    system.register('/opt/t', executable: true)
    expect([lookup.describe('ls'), lookup.describe('/opt/t')]).to eq(['ls is /usr/bin/ls', '/opt/t is /opt/t'])
    expect([lookup.find('ls').terse, lookup.find('/opt/t').terse]).to eq(['/usr/bin/ls', '/opt/t'])
  end

  it 'reports an unknown name, nil name or non-executable path as not known' do
    system.register('/usr/bin/plain', executable: false)
    system.register('/usr/bin/dircmd', type: :dir, executable: true)
    expect([lookup.find('nope_zzz').known?, lookup.find(nil).known?, lookup.find('/no/such').known?,
            lookup.find('plain').known?, lookup.find('dircmd').known?]).to eq([false, false, false, false, false])
    expect([lookup.describe('nope_zzz'), lookup.describe(nil)]).to eq([nil, nil])
  end

  it 'does not treat a bare name as a direct path before searching PATH' do
    system.register('tool', executable: true)
    expect(lookup.find('tool')).not_to be_known
  end

  it 'does not search PATH for a slash-containing name' do
    system.register('/usr/bin//opt/miss', executable: true)
    expect(lookup.find('/opt/miss')).not_to be_known
  end

  it 'searches an empty PATH element as the current directory' do
    env.assign('PATH', ':/usr/bin')
    system.register('tool', executable: true)
    expect(lookup.describe('tool')).to eq('tool is tool')
  end

  it 'keeps a trailing empty PATH element as the current directory' do
    env.assign('PATH', '/usr/bin:')
    system.register('tool', executable: true)
    expect(lookup.describe('tool')).to eq('tool is tool')
  end

  it 'treats an unset PATH as empty instead of failing lookup' do
    env.unset('PATH')
    system.register('tool', executable: true)
    expect(lookup.describe('tool')).to be_nil
  end

  it 'classifies an alias, returning its value, outranking a function or builtin' do
    state.aliases.define('ll', "ls 'quoted'")
    state.functions.define('ll', Rush::AST::SimpleCommand.new([], [], []))
    expect(lookup.describe('ll')).to eq("ll is an alias for ls 'quoted'")
    expect(lookup.find('ll').terse).to eq(%(alias 'll=ls '"'"'quoted'"'"''))
  end

  it 'lets a reserved word outrank an alias of the same name' do
    state.aliases.define('if', 'echo')
    expect(lookup.describe('if')).to eq('if is a shell keyword')
  end

  it 'searches an explicit path override instead of $PATH (command -p)' do
    system.register('/default/bin/tool', executable: true)
    override = described_class.new(executor, path: '/default/bin')
    expect([override.find('tool').terse, lookup.find('tool').known?]).to eq(['/default/bin/tool', false])
  end

  it 'resolves an executable path directly, bypassing the name resolvers' do
    system.register('/usr/bin/if', executable: true)
    expect([lookup.executable_path('if'), lookup.executable_path('nope_zzz')]).to eq(['/usr/bin/if', nil])
  end

  it 'caches only executable matches' do
    system.register('/usr/bin/ls', executable: true)
    cache = {}
    lookup.find('ls').cache_into(cache)
    lookup.find('echo').cache_into(cache)
    expect(cache).to eq('ls' => '/usr/bin/ls')
  end

  it 'requires Match subclasses to implement #describe and #terse' do
    base = Rush::CommandLookup::Match.new('x')
    cache = {}
    expect(base).to be_known
    base.cache_into(cache)
    expect(cache).to be_empty
    expect { base.describe }.to raise_error(NotImplementedError)
    expect { base.terse }.to raise_error(NotImplementedError)
  end
end
