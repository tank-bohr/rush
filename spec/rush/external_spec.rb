# frozen_string_literal: true

RSpec.describe Rush::External do
  let(:system) { instance_double(Rush::SystemCalls) }
  let(:jobs) { instance_double(Rush::JobTable) }
  let(:job_control) { instance_double(Rush::JobControl, monitored?: false) }
  let(:executor) { instance_double(Rush::Executor, system: system, jobs: jobs, job_control: job_control) }
  let(:io) { Rush::IoTable.standard(FakeSystemCalls.new) }

  before { allow(job_control).to receive(:foreground) { |_leader, &wait| wait.call } }

  def run(argv, table = io)
    described_class.new(executor, argv, table, {}).call
  end

  def capture_spawn_options
    options = nil
    allow(system).to receive(:spawn) do |_env, _argv, opts|
      options = opts
      11
    end
    allow(jobs).to receive(:await).with(11).and_return(Rush::Status.success)
    -> { options }
  end

  it 'spawns the program and awaits its status through the job table' do
    allow(system).to receive(:spawn).and_return(11)
    allow(jobs).to receive(:await).with(11).and_return(Rush::Status.new(3))
    expect(run(%w[prog a]).exitstatus).to eq(3)
  end

  it 'waits inside the job-control foreground wrapper, keyed on the spawned pid (terminal handover)' do
    allow(system).to receive(:spawn).and_return(11)
    allow(jobs).to receive(:await).with(11).and_return(Rush::Status.success)
    run(%w[prog])
    expect(job_control).to have_received(:foreground).with(11)
  end

  it 'spawns the command as its own process-group leader under job control (dash-probed)' do
    allow(job_control).to receive(:monitored?).and_return(true)
    options = capture_spawn_options
    run(%w[prog])
    expect(options.call).to include(pgroup: true)
  end

  it 'spawns without a process group while monitor is off' do
    options = capture_spawn_options
    run(%w[prog])
    expect(options.call).not_to include(:pgroup)
  end

  it 'returns 127 and a message when the program is not found' do
    allow(system).to receive(:spawn).and_raise(Errno::ENOENT)
    expect(run(%w[nope]).exitstatus).to eq(127)
    expect(io.get(2).string).to include('not found')
  end

  it 'returns 126 when the program is found but not executable' do
    allow(system).to receive(:spawn).and_raise(Errno::EACCES)
    expect(run(%w[adir]).exitstatus).to eq(126)
    expect(io.get(2).string).to include('Permission denied')
  end

  it 'keeps the lookup failure status when stderr is closed' do
    allow(system).to receive(:spawn).and_raise(Errno::ENOENT)
    expect(run(%w[nope], io.with_closed(2)).exitstatus).to eq(127)
  end
end
