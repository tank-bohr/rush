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
      signalled = Struct.new(:exitstatus, :termsig).new(nil, 9)
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

  describe '#clear_for_subshell' do
    it 'forgets recorded jobs and stashed statuses (a forked child has none)' do
      table.record(9)
      system.provide_child(7, 2)
      system.provide_child(5, 3)
      table.await(5)
      table.clear_for_subshell
      expect([table.wait_for(9), table.wait_for(7)]).to eq([nil, nil])
    end

    it 'drops a stashed foreign status too, not just the job entries' do
      table.record(9)
      system.provide_child(7, 2)
      system.provide_child(5, 3)
      table.await(5)
      table.clear_for_subshell
      expect(table.await(7)).to be_success
    end

    it 'drops the job-control environment — a forked child is no root and never reclaims the tty' do
      table.control.hold(Rush::Terminal.new(system: system, tty: StringIO.new, home: 4242, initial: 4242))
      table.clear_for_subshell
      expect([table.control.root, table.control.terminal]).to eq([false, nil])
    end
  end

  describe '#control' do
    it 'holds the acquired terminal until released (set +m)' do
      terminal = Rush::Terminal.new(system: system, tty: StringIO.new, home: 4242, initial: 4242)
      table.control.hold(terminal)
      expect(table.control.terminal).to be(terminal)
      table.control.hold(nil)
      expect(table.control.terminal).to be_nil
    end
  end

  describe '#wait_all' do
    it 'collects every known background job, leaving none running' do
      table.record(9)
      table.record(11)
      system.provide_child(11, 5)
      system.provide_child(9, 4)
      table.wait_all
      expect(table.ordered.map(&:running?)).to eq([false, false])
      expect([table.wait_for(9).exitstatus, table.wait_for(11).exitstatus]).to eq([4, 5])
    end
  end
end
