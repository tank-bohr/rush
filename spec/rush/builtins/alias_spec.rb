# frozen_string_literal: true

RSpec.describe Rush::Builtins::Alias do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['alias', *args], io).call
  end

  def aliases
    state.aliases
  end

  it 'defines an alias from name=value' do
    run('ll=ls -l')
    expect(aliases.value('ll')).to eq('ls -l')
  end

  it 'splits on the first = so the value may contain more' do
    run('a=b=c')
    expect(aliases.value('a')).to eq('b=c')
  end

  it 'allows an empty value' do
    run('a=')
    expect(aliases.value('a')).to eq('')
  end

  it 'defines several aliases at once' do
    run('a=1', 'b=2')
    expect([aliases.value('a'), aliases.value('b')]).to eq(%w[1 2])
  end

  it 'lists every alias as a single-quoted name=value, sorted, on stdout' do
    run('zzz=1', 'aaa=2')
    run
    expect(system.stdout.string).to eq("'aaa=2'\n'zzz=1'\n")
  end

  it 'quotes an embedded single quote dash-style when listing' do
    run("x=it's")
    run('x')
    expect(system.stdout.string).to eq(%('x=it'"'"'s'\n))
  end

  it 'prints a queried alias and succeeds' do
    run('ll=ls')
    expect([run('ll').exitstatus, system.stdout.string]).to eq([0, "'ll=ls'\n"])
  end

  it 'reports an unknown query on stderr with status 1' do
    status = run('nope')
    expect([status.exitstatus, system.stderr.string]).to eq([1, "alias: nope not found\n"])
  end

  it 'treats a leading = as a query, not a definition' do
    expect(run('=val').exitstatus).to eq(1)
  end

  it 'keeps defining after a failed query and ends with status 1' do
    status = run('a=1', 'missing', 'c=3')
    expect([status.exitstatus, aliases.value('a'), aliases.value('c')]).to eq([1, '1', '3'])
  end

  it 'succeeds and prints nothing when listing an empty table' do
    expect([run.exitstatus, system.stdout.string]).to eq([0, ''])
  end
end
