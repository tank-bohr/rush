# frozen_string_literal: true

RSpec.describe Rush::Builtins::Ulimit do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['ulimit', *args], io).call
  end

  it 'prints the soft file-size limit by default' do
    expect(run).to be_success
    expect(system.stdout.string).to eq("unlimited\n")
  end

  it 'prints selected soft and hard limits' do
    expect(run('-n')).to be_success
    expect(system.stdout.string).to eq("1024\n")

    system.stdout.truncate(0)
    system.stdout.rewind
    expect(run('-Hn')).to be_success
    expect(system.stdout.string).to eq("4096\n")
  end

  it 'lists all resources in dash format' do
    expect(run('-a')).to be_success
    expect(system.stdout.string).to include("time(seconds)        unlimited\n")
    expect(system.stdout.string).to include("nofiles              1024\n")
    expect(system.stdout.string).to include("rtprio               0\n")
  end

  it 'sets both limits by default' do
    expect(run('-n', '64')).to be_success
    expect(system.limits_set).to eq([[:nofile, 64, 64]])
  end

  it 'sets only the selected soft or hard limit' do
    expect(run('-Sn', '64')).to be_success
    expect(run('-Hn', '128')).to be_success
    expect(system.limits_set).to eq([[:nofile, 64, 4096], [:nofile, 64, 128]])
  end

  it 'scales block and kbyte resources when setting them' do
    expect(run('-f', '2')).to be_success
    expect(run('-s', '3')).to be_success
    expect(system.limits_set).to eq([[:fsize, 1024, 1024], [:stack, 3072, 3072]])
  end

  it 'sets unlimited to the platform infinity value' do
    expect(run('-f', 'unlimited')).to be_success
    expect(system.limits_set).to eq([[:fsize, system.infinity_limit, system.infinity_limit]])
  end

  it 'rejects an illegal option' do
    status = run('-z')
    expect([status.exitstatus, system.stderr.string]).to eq([2, "rush: ulimit: Illegal option -z\n"])
  end

  it 'rejects a bare dash as an illegal option' do
    status = run('-')
    expect([status.exitstatus, system.stderr.string]).to eq([2, "rush: ulimit: Illegal option -\n"])
  end

  it 'rejects a limit operand with list-all' do
    status = run('-a', '1')
    expect([status.exitstatus, system.stderr.string]).to eq([2, "rush: ulimit: too many arguments\n"])
  end

  it 'reports setrlimit failures' do
    allow(system).to receive(:setrlimit).and_raise(Errno::EINVAL)
    status = run('-n', '64')
    expect([status.exitstatus, system.stderr.string]).to eq([2, "rush: ulimit: error setting limit\n"])
  end

  it 'rejects a non-numeric limit' do
    status = run('-n', 'nope')
    expect([status.exitstatus, system.stderr.string]).to eq([2, "rush: ulimit: Illegal number: nope\n"])
  end

  it 'rejects extra operands' do
    status = run('-n', '1', '2')
    expect([status.exitstatus, system.stderr.string]).to eq([2, "rush: ulimit: too many arguments\n"])
  end
end
