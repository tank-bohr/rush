# frozen_string_literal: true

RSpec.describe Rush::JobTable do
  subject(:table) { described_class.new(system) }

  let(:system) { FakeSystemCalls.new }

  describe '#await' do
    it 'waits for the pid directly while no background job is running' do
      system.provide_child(5, 3)
      expect(table.await(5).exitstatus).to eq(3)
    end

    it 'reaps any child once a background job is running, filing the status on its entry' do
      table.record(9)
      system.provide_child(9, 1)
      system.provide_child(5, 3)
      expect(table.await(5).exitstatus).to eq(3)
      expect(table.current.running?).to be(false)
      expect(table.wait_for(9).exitstatus).to eq(1)
    end

    it 'targets the pid directly with no live background job, waitpid(-1) once one runs' do
      allow(system).to receive(:waitpid2).and_call_original
      system.provide_child(5, 3)
      table.await(5)
      expect(system).to have_received(:waitpid2).with(5)
      table.record(9)
      system.provide_child(6, 0)
      table.await(6)
      expect(system).to have_received(:waitpid2).with(-1)
    end

    it 'returns to direct waits once every background job is reaped' do
      table.record(9)
      system.provide_child(9, 1)
      table.wait_for(9)
      allow(system).to receive(:waitpid2).and_call_original
      system.provide_child(5, 3)
      table.await(5)
      expect(system).to have_received(:waitpid2).with(5)
    end

    it 'consults the stash before waiting, so a sibling reaped early is not lost' do
      table.record(9)
      system.provide_child(7, 2)
      system.provide_child(5, 3)
      table.await(5)
      expect(table.await(7).exitstatus).to eq(2)
    end

    it 'maps a signalled child to 128 + signal' do
      signalled = FakeSystemCalls::ChildStatus.new(nil, 9)
      allow(system).to receive(:waitpid2).with(5).and_return([5, signalled])
      expect(table.await(5).exitstatus).to eq(137)
    end

    it 'answers success when every child is gone (the ECHILD guard)' do
      table.record(9)
      expect(table.await(5)).to be_success
    end
  end

  describe '#record' do
    it 'ignores the fake fork sentinel pid 0' do
      table.record(0)
      expect(table.wait_for(0)).to be_nil
    end

    it 'stamps the entry with the rendered text it was given' do
      table.record(9, text: 'sleep 9 | cat')
      expect([table.current.text, table.current.controlled?]).to eq(['sleep 9 | cat', true])
    end

    it 'numbers jobs from 1, reusing the lowest freed slot' do
      table.record(11)
      table.record(12)
      table.forget(table.numbered(1))
      table.record(13)
      expect([table.numbered(1).pid, table.ordered.map(&:number)]).to eq([13, [1, 2]])
    end
  end

  describe '#current and #previous' do
    it 'track recency, newest first, regardless of job numbers' do
      table.record(11)
      table.record(12)
      expect([table.current.pid, table.previous.pid]).to eq([12, 11])
    end

    it 'are nil while the table is empty' do
      expect([table.current, table.previous]).to eq([nil, nil])
    end
  end

  describe '#poll' do
    it 'collects finished children without blocking, settling their entries' do
      table.record(9)
      system.provide_child(9, 4)
      expect { table.poll }.to change { table.current.running? }.from(true).to(false)
      expect(table.wait_for(9).exitstatus).to eq(4)
    end

    it 'is a no-op with nothing to reap' do
      expect { table.poll }.not_to raise_error
    end

    it 'swallows ECHILD when there are no children at all' do
      allow(system).to receive(:poll_child).and_raise(Errno::ECHILD)
      expect { table.poll }.not_to raise_error
    end
  end

  describe '#wait_for' do
    it 'returns nil for a pid that was never a background job' do
      expect(table.wait_for(41)).to be_nil
    end

    it 'blocks on a live background job and remembers its status for repeats' do
      table.record(9)
      system.provide_child(9, 4)
      expect(table.wait_for(9).exitstatus).to eq(4)
      expect(table.wait_for(9).exitstatus).to eq(4)
    end

    it 'wraps the reaped process status as a shell Status' do
      table.record(9)
      system.provide_child(9, 0)
      expect(table.wait_for(9)).to be_success
    end

    it 'reports success when the child is gone (the defensive ECHILD guard)' do
      table.record(9)
      expect(table.wait_for(9)).to be_success
      expect(table.wait_for(9)).to be_success
    end
  end

  describe '#enter_subshell' do
    it 'demotes entries to unwaitable display copies (POSIX 2.12: wait answers 127 through nil)' do
      table.record(9)
      system.provide_child(7, 2)
      system.provide_child(5, 3)
      table.await(5)
      table.enter_subshell
      expect([table.wait_for(9), table.wait_for(7)]).to eq([nil, nil])
    end

    it 'keeps the entries listable — the duplicate environment still shows them to jobs' do
      table.record(9)
      table.enter_subshell
      job = table.ordered.fetch(0)
      expect([job.pid, job.inherited?, table.current]).to eq([9, true, job])
    end

    it 'drops a stashed foreign status too, not just the waitability' do
      table.record(9)
      system.provide_child(7, 2)
      system.provide_child(5, 3)
      table.await(5)
      table.enter_subshell
      expect(table.await(7)).to be_success
    end

    it 'never lets an inherited running entry force waitpid(-1): a direct await still answers' do
      table.record(9)
      table.enter_subshell
      system.wait_status = FakeSystemCalls::ChildStatus.new(5, nil)
      expect(table.await(11).exitstatus).to eq(5)
    end

    it 'drops the job-control environment — a forked child is no root and never reclaims the tty' do
      table.control.engage(Rush::Terminal.new(system: system, tty: StringIO.new, home: 4242, initial: 4242))
      table.enter_subshell
      expect([table.control.root, table.control.terminal]).to eq([false, nil])
    end
  end

  describe '#control' do
    it 'holds the acquired terminal until released (set +m)' do
      terminal = Rush::Terminal.new(system: system, tty: StringIO.new, home: 4242, initial: 4242)
      table.control.engage(terminal)
      expect([table.control.terminal, table.control.monitor?]).to eq([terminal, true])
      table.control.release
      expect([table.control.terminal, table.control.monitor?]).to eq([nil, false])
    end

    it 'arms the stage relay only under monitor, and the relay survives the fork (rush-l4o)' do
      table.control.arm_stage_relay
      expect(table.control.relay?).to be(false)
      table.control.engage(nil)
      table.control.arm_stage_relay
      table.control.fork_child
      expect([table.control.relay?, table.control.monitor?, table.control.stoppable_waits?])
        .to eq([true, false, true])
    end

    it 'drops an armed relay when job control is explicitly released (set +m in the stage)' do
      table.control.engage(nil)
      table.control.arm_stage_relay
      table.control.release
      expect([table.control.relay?, table.control.stoppable_waits?]).to eq([false, false])
    end
  end

  describe 'the stage stop relay (rush-l4o)' do
    before do
      table.control.engage(nil)
      table.control.arm_stage_relay
      table.control.fork_child
    end

    it 're-raises a reaped stop onto itself (default disposition first) and re-waits the target' do
      system.provide_stopped(9, 20)
      system.provide_child(9, 5)
      expect(table.await(9).exitstatus).to eq(5)
      expect(system.kills).to eq([['TSTP', 4242]])
      expect(system.traps_installed).to include(%w[TSTP SYSTEM_DEFAULT])
    end

    it 'skips the untrappable STOP disposition but still re-raises the stop' do
      system.provide_stopped(9, 19)
      system.provide_child(9, 0)
      expect(table.await(9)).to be_success
      expect(system.kills).to eq([['STOP', 4242]])
      expect(system.traps_installed).to be_empty
    end
  end

  describe 'stopped jobs (rush-mv8.4)' do
    before { table.control.engage(nil) }

    it 'reaps a stop through the monitored wait: 128+stopsig, entry parked Stopped' do
      table.record(9)
      system.provide_stopped(9, 20)
      expect(table.wait_for(9).exitstatus).to eq(148)
      expect([table.current.stopped?, table.current.finished?]).to eq([true, false])
    end

    it 'answers a stopped job repeatably, then follows its death once reaped' do
      table.record(9)
      system.provide_stopped(9, 20)
      table.poll
      expect(table.wait_for(9).exitstatus).to eq(148)
      system.provide_signalled(9, 9)
      table.poll
      expect(table.wait_for(9).exitstatus).to eq(137)
    end

    it 'awaits a foreground child through the stoppable wait under monitor' do
      allow(system).to receive(:wait_stoppable).and_call_original
      system.provide_stopped(5, 20)
      status = table.await(5)
      expect([status.exitstatus, status.stopsig]).to eq([148, 20])
      expect(system).to have_received(:wait_stoppable).with(5)
    end

    it 'keeps waitpid(-1) reaping while a stopped job could still change state' do
      table.record(9)
      system.provide_stopped(9, 19)
      table.poll
      allow(system).to receive(:wait_stoppable).and_call_original
      system.provide_child(5, 3)
      expect(table.await(5).exitstatus).to eq(3)
      expect(system).to have_received(:wait_stoppable).with(-1)
    end

    it 'stashes a foreign sibling stop for its own await to consume' do
      table.record(9)
      system.provide_stopped(5, 20)
      system.provide_child(7, 3)
      expect(table.await(7).exitstatus).to eq(3)
      expect(table.await(5).exitstatus).to eq(148)
    end
  end

  describe '#adopt_stopped' do
    it 'parks a ^Z-stopped foreground pipeline as one Stopped entry, leader first' do
      table.adopt_stopped([50, 51], 20)
      job = table.current
      expect([job.number, job.pid, job.members, job.stopped?]).to eq([1, 50, [50, 51], true])
    end

    it 'ignores the fake fork sentinel leader pid 0' do
      table.adopt_stopped([0], 20)
      expect(table.current).to be_nil
    end

    it 're-parks an existing entry: same number, members and text survive' do
      table.adopt_stopped([50, 51], 20, 'sleep 9')
      table.current.resume
      table.adopt_stopped([50, 51], 19, 'ignored — the entry exists')
      job = table.current
      expect([job.number, job.members, job.text, job.stopsig]).to eq([1, [50, 51], 'sleep 9', 19])
    end
  end

  describe '#settle_members (fg wait over a resumed job)' do
    it 'waits the leader through its entry and the rest through the stash-aware await' do
      table.control.engage(nil)
      table.adopt_stopped([50, 51], 20, 'sleep 9')
      table.current.resume
      system.provide_child(50, 0)
      system.provide_child(51, 7)
      verdict = table.settle_members(table.current)
      expect([verdict.exitstatus, verdict.stopped?]).to eq([7, false])
    end

    it 'carries a member stop onto the verdict' do
      table.control.engage(nil)
      table.adopt_stopped([50, 51], 20, 'sleep 9')
      table.current.resume
      system.provide_stopped(50, 20)
      system.provide_child(51, 5)
      verdict = table.settle_members(table.current)
      expect([verdict.exitstatus, verdict.stopsig]).to eq([5, 20])
    end
  end

  describe '#announce_changed (pre-prompt notifications)' do
    it 'polls, reports every changed job newest-first to the stream, frees the finished' do
      table.control.engage(nil)
      table.record(9, text: 'sleep 9')
      table.record(11, text: 'sleep 11')
      system.provide_child(9, 0)
      system.provide_signalled(11, 9)
      out = StringIO.new
      table.announce_changed(out)
      expect(out.string).to eq("#{'[2] + Killed'.ljust(33)}sleep 11\n#{'[1] + Done'.ljust(33)}sleep 9\n")
      expect(table.current).to be_nil
    end

    it 'reports nothing while nothing changed, and never repeats a report' do
      table.control.engage(nil)
      table.record(9, text: 'sleep 9')
      out = StringIO.new
      table.announce_changed(out)
      system.provide_stopped(9, 20)
      table.announce_changed(out)
      table.announce_changed(out)
      expect(out.string).to eq("#{'[1] + Stopped'.ljust(33)}sleep 9\n")
      expect(table.current.stopped?).to be(true)
    end
  end

  describe '#poll under monitor' do
    it 'uses the stoppable poll only when the machinery is engaged' do
      allow(system).to receive(:poll_child).and_call_original
      allow(system).to receive(:poll_stopped).and_call_original
      table.poll
      expect(system).to have_received(:poll_child)
      table.control.engage(nil)
      table.poll
      expect(system).to have_received(:poll_stopped)
    end
  end

  describe 'Control#warn_exit? / #tick_warning (dash job_warning)' do
    it 'starts as the root shell, machinery off, no terminal, warning disarmed' do
      control = table.control
      expect([control.root, control.monitor?, control.terminal]).to eq([true, false, nil])
      control.tick_warning
      expect(control.warn_exit?).to be(true)
    end

    it 'refuses once, lets an immediate retry through, and re-arms two ticks later' do
      expect(table.control.warn_exit?).to be(true)
      table.control.tick_warning
      expect(table.control.warn_exit?).to be(false)
      table.control.tick_warning
      expect(table.control.warn_exit?).to be(true)
    end

    it 'never re-arms without ticks (a batch shell exits on the second try)' do
      results = [table.control.warn_exit?, table.control.warn_exit?, table.control.warn_exit?]
      expect(results).to eq([true, false, false])
    end
  end
end
