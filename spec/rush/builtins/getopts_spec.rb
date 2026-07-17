# frozen_string_literal: true

RSpec.describe Rush::Builtins::Getopts do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['getopts', *args], io).call
  end

  def vars(*names)
    names.map { |name| state.variables.get(name) }
  end

  def snapshot(status, *names)
    [status.exitstatus, *vars(*names)]
  end

  it 'initializes OPTIND to 1' do
    expect(state.variables.get('OPTIND')).to eq('1')
  end

  it 'reports usage when required operands are missing' do
    expect(run('a').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("getopts: Usage: getopts optstring var [arg...]\n")
  end

  it 'keeps the usage status when stderr is closed' do
    status = described_class.new(executor, %w[getopts a], io.with_closed(2)).call
    expect(status.exitstatus).to eq(2)
  end

  it 'parses clustered options from positional parameters' do
    state.positional.replace(%w[-ab])
    first = snapshot(run('ab', 'opt'), 'opt', 'OPTIND', 'OPTARG')
    second = snapshot(run('ab', 'opt'), 'opt', 'OPTIND', 'OPTARG')
    done = snapshot(run('ab', 'opt'), 'opt', 'OPTIND')
    expect([first, second, done]).to eq([[0, 'a', '2', ''], [0, 'b', '2', ''], [1, '?', '2']])
  end

  it 'parses required option arguments from attached and following words' do
    state.positional.replace(%w[-bVALUE -c next])
    first = snapshot(run('b:c:', 'opt'), 'opt', 'OPTIND', 'OPTARG')
    second = snapshot(run('b:c:', 'opt'), 'opt', 'OPTIND', 'OPTARG')
    expect([first, second]).to eq([[0, 'b', '2', 'VALUE'], [0, 'c', '4', 'next']])
  end

  it 'uses explicit args instead of positional parameters' do
    state.positional.replace(%w[-x])
    expect(run('a', 'opt', '-a').exitstatus).to eq(0)
    expect(vars('opt', 'OPTIND', 'OPTARG')).to eq(%w[a 2] + [''])
  end

  it 'stops at -- and at the first non-option word' do
    state.positional.replace(%w[-- tail])
    expect(run('a', 'opt').exitstatus).to eq(1)
    expect(vars('opt', 'OPTIND')).to eq(%w[? 2])
    state.variables.assign('OPTIND', '1')
    state.positional.replace(%w[word])
    expect(run('a', 'opt').exitstatus).to eq(1)
    expect(vars('opt', 'OPTIND')).to eq(%w[? 1])
  end

  it 'resets the hidden cluster cursor when OPTIND is reset to 1' do
    state.positional.replace(%w[-ab])
    run('ab', 'opt')
    state.variables.assign('OPTIND', '1')
    run('ab', 'opt')
    expect(vars('opt', 'OPTIND')).to eq(%w[a 2])
  end

  it 'treats invalid or non-positive OPTIND as 1' do
    state.positional.replace(%w[-a])
    state.variables.assign('OPTIND', 'bad')
    first = snapshot(run('a', 'opt'), 'opt', 'OPTIND')
    state.variables.assign('OPTIND', '0')
    second = snapshot(run('a', 'opt'), 'opt', 'OPTIND')
    expect([first, second]).to eq([[0, 'a', '2'], [0, 'a', '2']])
  end

  it 'reports invalid options in normal mode' do
    state.positional.replace(%w[-x])
    state.variables.assign('OPTARG', 'old')
    state.variables.export('OPTARG')
    expect(run('a', 'opt').exitstatus).to eq(0)
    expect([*vars('opt', 'OPTIND', 'OPTARG'), system.stderr.string]).to eq(['?', '2', nil, "Illegal option -x\n"])
    expect(state.variables.exported).not_to include('OPTARG')
  end

  it 'reports invalid options in silent mode without diagnostics' do
    state.positional.replace(%w[-x])
    expect(run(':a', 'opt').exitstatus).to eq(0)
    expect([*vars('opt', 'OPTIND', 'OPTARG'), system.stderr.string]).to eq(['?', '2', 'x', ''])
  end

  it 'reports a missing argument in normal mode' do
    state.positional.replace(%w[-a])
    expect(run('a:', 'opt').exitstatus).to eq(0)
    expect([*vars('opt', 'OPTIND', 'OPTARG'), system.stderr.string]).to eq(['?', '2', nil, "No arg for -a option\n"])
  end

  it 'reports a missing argument in silent mode without diagnostics' do
    state.positional.replace(%w[-a])
    expect(run(':a:', 'opt').exitstatus).to eq(0)
    expect([*vars('opt', 'OPTIND', 'OPTARG'), system.stderr.string]).to eq([':', '2', 'a', ''])
  end

  it 'leaves OPTARG untouched at end of options (the KEEP sentinel)' do
    state.positional.replace(%w[-a val])
    run('a:', 'opt')
    expect(run('a:', 'opt').exitstatus).to eq(1)
    expect(vars('opt', 'OPTARG')).to eq(['?', 'val'])
  end

  it 'restarts from position 1 when OPTIND is unset instead of crashing' do
    state.variables.unset('OPTIND')
    state.positional.replace(%w[-a])
    expect(snapshot(run('a', 'opt'), 'opt', 'OPTIND')).to eq([0, 'a', '2'])
  end

  it 'restarts from position 1 for a zero, negative, or garbage OPTIND' do
    %w[0 -3 junk].each do |value|
      state.variables.assign('OPTIND', value)
      state.positional.replace(%w[-a])
      expect(snapshot(run('a', 'opt'), 'opt', 'OPTIND')).to eq([0, 'a', '2'])
    end
  end
end
