# frozen_string_literal: true

RSpec.describe Rush::JobTable::Job do
  subject(:job) { described_class.new(1, 50, members: [50, 51]) }

  it 'starts running, with the leader pid and every member listed' do
    expect([job.number, job.pid, job.members, job.running?]).to eq([1, 50, [50, 51], true])
  end

  it 'defaults members to the single pid' do
    expect(described_class.new(1, 50).members).to eq([50])
  end

  it 'routes a stop to the parked state: alive, re-waitable, not finished' do
    job.finish(FakeSystemCalls::ChildStatus.new(nil, nil, 20))
    expect([job.running?, job.stopped?, job.finished?]).to eq([false, true, false])
  end

  it 'answers 128+stopsig while stopped, immediately and repeatably (dash-probed wait %1)' do
    job.stop(20)
    expect([job.harvest { raise ArgumentError, 'must not wait' }.exitstatus, job.status.exitstatus]).to eq([148, 148])
  end

  it 'settles for good on a final status, Done beating the earlier stop' do
    job.stop(20)
    job.finish(FakeSystemCalls::ChildStatus.new(nil, 9))
    expect([job.stopped?, job.finished?, job.status.exitstatus]).to eq([false, true, 137])
  end

  it 'harvests a running job through the supplied wait, which may itself park it' do
    status = job.harvest { FakeSystemCalls::ChildStatus.new(nil, nil, 19) }
    expect([status.exitstatus, job.stopped?]).to eq([147, true])
  end

  it 'remembers a final harvest without re-waiting (dash never frees on wait)' do
    job.harvest { FakeSystemCalls::ChildStatus.new(4, nil) }
    expect(job.harvest { raise ArgumentError, 'must not wait' }.exitstatus).to eq(4)
  end

  it 'answers stopsig only while parked' do
    expect(job.stopsig).to be_nil
    job.stop(19)
    expect(job.stopsig).to eq(19)
    job.finish(FakeSystemCalls::ChildStatus.new(0, nil))
    expect(job.stopsig).to be_nil
  end

  it 'exposes the identity: text for display, its presence as the jobctl stamp' do
    stamped = described_class.new(1, 50, text: 'sleep 9')
    expect([stamped.text, stamped.controlled?]).to eq(['sleep 9', true])
    expect([job.text, job.controlled?]).to eq(['', false])
  end

  describe '#display_state (dash statusfmt vocabulary)' do
    it 'says Running while nothing was reaped' do
      expect(job.display_state).to eq('Running')
    end

    it 'spells every Stopped flavour by signal' do
      states = [20, 19, 21, 22].map do |sig|
        job.stop(sig)
        job.display_state
      end
      expect(states).to eq(['Stopped', 'Stopped (signal)', 'Stopped (tty input)', 'Stopped (tty output)'])
    end

    it 'says Done for a clean exit and Done(n) for a code' do
      job.finish(FakeSystemCalls::ChildStatus.new(0, nil))
      expect(job.display_state).to eq('Done')
      job.finish(FakeSystemCalls::ChildStatus.new(5, nil))
      expect(job.display_state).to eq('Done(5)')
    end

    it 'describes the killing signal' do
      job.finish(FakeSystemCalls::ChildStatus.new(nil, 9))
      expect(job.display_state).to eq('Killed')
      job.finish(FakeSystemCalls::ChildStatus.new(nil, 15))
      expect(job.display_state).to eq('Terminated')
    end
  end

  describe '#changed / #reported (the notification bit)' do
    it 'starts unchanged: a fresh launch is not announced (dash prints no launch line)' do
      expect(job.changed).to be(false)
    end

    it 'flips on finish and on stop, and clears when reported' do
      job.stop(20)
      expect(job.changed).to be(true)
      job.reported
      expect(job.changed).to be(false)
      job.finish(FakeSystemCalls::ChildStatus.new(0, nil))
      expect(job.changed).to be(true)
    end
  end

  describe '#resume / #continue' do
    it 'resume clears a stop (and its pending announcement); a settled job stays put' do
      job.stop(20)
      job.resume
      expect([job.running?, job.changed]).to eq([true, false])
      job.finish(FakeSystemCalls::ChildStatus.new(0, nil))
      job.resume
      expect(job.finished?).to be(true)
    end

    it 'continue resumes and SIGCONTs the leader group' do
      system = FakeSystemCalls.new
      job.stop(20)
      job.continue(system)
      expect([job.running?, system.kills]).to eq([true, [['CONT', -50]]])
    end

    it 'continue swallows ESRCH for a group already gone' do
      system = FakeSystemCalls.new(dead_pids: [-50])
      job.stop(20)
      expect { job.continue(system) }.not_to raise_error
      expect(job.running?).to be(true)
    end
  end

  describe '#report' do
    let(:table) { Rush::JobTable.new(FakeSystemCalls.new) }

    it 'prints the showjob line, clears changed and keeps a stopped entry' do
      table.adopt_stopped([50], 20, 'sleep 9')
      out = StringIO.new
      entry = table.current
      entry.report(table, out)
      expect(out.string).to eq("#{'[1] + Stopped'.ljust(33)}sleep 9\n")
      expect([entry.changed, table.current]).to eq([false, entry])
    end

    it 'frees a finished entry after printing it' do
      table.adopt_stopped([50], 20, 'sleep 9')
      table.current.finish(FakeSystemCalls::ChildStatus.new(nil, 9))
      out = StringIO.new
      table.current.report(table, out)
      expect(out.string).to eq("#{'[1] + Killed'.ljust(33)}sleep 9\n")
      expect(table.current).to be_nil
    end
  end
end
