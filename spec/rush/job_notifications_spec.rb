# frozen_string_literal: true

RSpec.describe 'pre-prompt job notifications' do # rubocop:disable RSpec/DescribeClass -- a Repl seam
  let(:system) { FakeSystemCalls.new(stdin: '') }
  let(:state) { Rush::ShellState.new }
  let(:repl) { Rush::Repl.new(system, state: state) }
  let(:jobs) { repl.send(:executor).jobs }

  def prompt
    repl.send(:prompt_line, false)
  end

  def engage_with_job(text: 'sleep 9')
    jobs.control.engage(nil)
    jobs.record(9, text: text)
  end

  it 'reports a finished background job before the prompt, then frees it (dash showjobs SHOW_CHANGED)' do
    engage_with_job
    system.provide_child(9, 0)
    prompt
    expect(system.stderr.string).to start_with("#{'[1] + Done'.ljust(33)}sleep 9\n")
    expect(jobs.current).to be_nil
  end

  it 'reports a stop without freeing, and only once' do
    engage_with_job
    system.provide_stopped(9, 19)
    prompt
    prompt
    expect(system.stderr.string.scan('Stopped (signal)').size).to eq(1)
    expect(jobs.current.stopped?).to be(true)
  end

  it 'reports a state already collected by the wait builtin (dash notifies after wait too)' do
    engage_with_job
    system.provide_signalled(9, 9)
    jobs.wait_for(9)
    prompt
    expect(system.stderr.string).to include("#{'[1] + Killed'.ljust(33)}sleep 9\n")
    expect(jobs.current).to be_nil
  end

  it 'stays silent without monitor mode (dash-probed: set +m silences the reports)' do
    jobs.record(9)
    system.provide_child(9, 0)
    prompt
    expect(system.stderr.string).not_to include('Done')
  end

  it 'stays silent when the jobs listing already displayed the change' do
    engage_with_job
    system.provide_stopped(9, 20)
    jobs.poll
    jobs.current.reported
    prompt
    expect(system.stderr.string).not_to include('Stopped')
  end

  it 'skips continuation prompts (a state change mid-command waits for PS1)' do
    engage_with_job
    system.provide_child(9, 0)
    repl.send(:prompt_line, true)
    expect(system.stderr.string).not_to include('Done')
  end
end
