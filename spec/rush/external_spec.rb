# frozen_string_literal: true

RSpec.describe Rush::External do
  let(:system) { instance_double(Rush::SystemCalls, stderr: StringIO.new) }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { instance_double(Rush::Executor, system: system, state: state) }

  def run(argv) = described_class.new(executor, argv).call

  it 'spawns the program and translates its exit status' do
    process_status = instance_double(Process::Status, exitstatus: 3, termsig: nil)
    allow(system).to receive(:spawn).and_return(11)
    allow(system).to receive(:waitpid2).with(11).and_return([11, process_status])
    expect(run(%w[prog a]).exitstatus).to eq(3)
  end

  it 'returns 127 and a message when the program is not found' do
    allow(system).to receive(:spawn).and_raise(Errno::ENOENT)
    expect(run(%w[nope]).exitstatus).to eq(127)
    expect(system.stderr.string).to include('not found')
  end

  it 'returns 126 when the program is found but not executable' do
    allow(system).to receive(:spawn).and_raise(Errno::EACCES)
    expect(run(%w[adir]).exitstatus).to eq(126)
    expect(system.stderr.string).to include('Permission denied')
  end
end
