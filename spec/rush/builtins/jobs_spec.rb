# frozen_string_literal: true

RSpec.describe Rush::Builtins::Jobs do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['jobs', *args], io).call
  end

  def record(*pids)
    pids.each { |pid| executor.jobs.record(pid) }
  end

  it 'lists jobs newest first with + and - marks, padded to the command column' do
    record(11, 12, 13)
    expect(run).to be_success
    expect(system.stdout.string)
      .to eq("#{'[3] + Running'.ljust(33)}\n#{'[2] - Running'.ljust(33)}\n#{'[1]   Running'.ljust(33)}\n")
  end

  it 'renders Done, Done(n) and signal descriptions after polling finished children' do
    record(11, 12, 13)
    system.provide_child(11, 0)
    system.provide_child(12, 5)
    system.provide_signalled(13, 9)
    run
    # every line carries +: freeing each displayed entry re-promotes the
    # next to current before it prints, exactly as dash renders this
    expect(system.stdout.string)
      .to eq("#{'[3] + Killed'.ljust(33)}\n#{'[2] + Done(5)'.ljust(33)}\n#{'[1] + Done'.ljust(33)}\n")
  end

  it 'frees a finished job once displayed, so wait no longer knows it' do
    record(11)
    system.provide_child(11, 5)
    run
    expect(executor.jobs.wait_for(11)).to be_nil
  end

  it 'prints only pids under -p, newest first, without freeing finished jobs' do
    record(11, 12)
    system.provide_child(11, 5)
    expect(run('-p')).to be_success
    expect(system.stdout.string).to eq("12\n11\n")
    expect(executor.jobs.wait_for(11).exitstatus).to eq(5)
  end

  it 'inserts the pid after the mark under -l' do
    record(11)
    run('-l')
    expect(system.stdout.string).to eq("#{'[1] + 11 Running'.ljust(33)}\n")
  end

  it 'combines a flag with %id operands (dash: jobs -l %1)' do
    record(11, 12)
    expect(run('-l', '%1')).to be_success
    expect(system.stdout.string).to eq("#{'[1] - 11 Running'.ljust(33)}\n")
  end

  it 'renders the jobs %ids select, aborting on the first unknown after rendering' do
    record(11, 12)
    expect(run('%1', '%9').exitstatus).to eq(2)
    expect(system.stdout.string).to eq("#{'[1] - Running'.ljust(33)}\n")
    expect(system.stderr.string).to eq("jobs: No such job: %9\n")
  end

  it 'renders every Stopped flavour by stop signal, exactly as dash prints strsignal' do
    record(11, 12, 13, 14)
    executor.jobs.control.engage(nil)
    [[11, 20], [12, 19], [13, 21], [14, 22]].each { |pid, sig| system.provide_stopped(pid, sig) }
    run
    expect(system.stdout.string.split("\n").map(&:rstrip))
      .to eq(['[4] + Stopped (tty output)', '[3] - Stopped (tty input)',
              '[2]   Stopped (signal)', '[1]   Stopped'])
  end

  it 'keeps a Stopped entry after displaying it — only finished jobs are freed (dash-probed)' do
    record(11)
    executor.jobs.control.engage(nil)
    system.provide_stopped(11, 20)
    run
    run
    expect(system.stdout.string.split("\n").map(&:rstrip)).to eq(['[1] + Stopped', '[1] + Stopped'])
  end

  it 'rejects an unknown flag with status 2' do
    expect(run('-x').exitstatus).to eq(2)
    expect(system.stderr.string).to eq("jobs: Illegal option -x\n")
  end

  it 'prints nothing for an empty table' do
    expect(run).to be_success
    expect(system.stdout.string).to be_empty
  end
end
