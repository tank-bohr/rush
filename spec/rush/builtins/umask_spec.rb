# frozen_string_literal: true

RSpec.describe Rush::Builtins::Umask do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['umask', *args], io).call
  end

  it 'prints the current mask in octal by default' do
    expect(run).to be_success
    expect(system.stdout.string).to eq("0022\n")
  end

  it 'prints the current mask symbolically with -S' do
    expect(run('-S')).to be_success
    expect(system.stdout.string).to eq("u=rwx,g=rx,o=rx\n")
  end

  it 'sets an octal mask' do
    expect(run('077')).to be_success
    expect(system.current_umask).to eq(0o077)
  end

  it 'sets a symbolic mask' do
    expect(run('go=')).to be_success
    expect(system.current_umask).to eq(0o077)
  end

  it 'uses only the first mode operand like dash' do
    expect(run('022', '077')).to be_success
    expect(system.current_umask).to eq(0o022)
  end

  it 'rejects an illegal option' do
    status = run('-w')
    expect([status.exitstatus, system.stderr.string]).to eq([2, "rush: umask: Illegal option -w\n"])
  end

  it 'rejects an illegal mode' do
    status = run('abc')
    expect([status.exitstatus, system.stderr.string]).to eq([2, "rush: umask: Illegal mode: abc\n"])
  end

  it 'rejects an illegal octal number' do
    status = run('999')
    expect([status.exitstatus, system.stderr.string]).to eq([2, "rush: umask: Illegal number: 999\n"])
  end
end
