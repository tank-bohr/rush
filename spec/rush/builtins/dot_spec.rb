# frozen_string_literal: true

RSpec.describe Rush::Builtins::Dot do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['.', *args], io).call

  it 'runs the file in the current shell, persisting its definitions' do
    system.provide_file('/lib.sh', "greet() { echo hi; }\nX=loaded\n")
    expect(run('/lib.sh')).to be_success
    expect(state.environment.get('X')).to eq('loaded')
    expect(state.functions.key?('greet')).to be(true)
  end

  it 'reports a missing file' do
    expect(run('/nope.sh')).not_to be_success
    expect(system.stderr.string).to include('No such file or directory')
  end

  it 'reports a syntax error in the file' do
    system.provide_file('/bad.sh', 'if')
    expect(run('/bad.sh').exitstatus).to eq(1)
    expect(system.stderr.string).to include('.:')
  end

  it 'errors with exit status 2 when given no filename' do
    expect(run.exitstatus).to eq(2)
    expect(system.stderr.string).to include('filename argument required')
  end

  it 'propagates exit from the sourced file' do
    system.provide_file('/x.sh', 'exit 4')
    expect { run('/x.sh') }.to raise_error(Rush::ExitSignal) { |e| expect(e.code).to eq(4) }
  end
end
