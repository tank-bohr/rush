# frozen_string_literal: true

RSpec.describe Rush::Builtins::NoJobControl do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run_as(name, *args)
    described_class.new(executor, [name, *args], io).call
  end

  it 'reports No current job when the table is empty' do
    expect(run_as('fg').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("fg: No current job\n")
  end

  it 'refuses the current job: not created under job control' do
    executor.jobs.record(11)
    expect(run_as('fg').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("fg: job not created under job control\n")
  end

  it 'echoes the operand in the refusal, under the invoked name' do
    executor.jobs.record(11)
    expect(run_as('bg', '%1').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("bg: job %1 not created under job control\n")
  end

  it 'reports No such job for an unresolvable operand' do
    expect(run_as('bg', '%7').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("bg: No such job: %7\n")
  end
end
