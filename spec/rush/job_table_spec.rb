# frozen_string_literal: true

RSpec.describe Rush::JobTable do
  subject(:table) { described_class.new(system) }

  let(:system) { FakeSystemCalls.new }

  describe '#await' do
    it 'waits for the pid directly while no background job is running' do
      system.provide_child(5, 3)
      expect(table.await(5).exitstatus).to eq(3)
    end

    it 'reaps any child once a background job is running, filing its status' do
      table.record(9)
      system.provide_child(9, 1)
      system.provide_child(5, 3)
      expect(table.await(5).exitstatus).to eq(3)
      expect(table.wait_for(9).exitstatus).to eq(1)
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
  end

  describe '#record' do
    it 'ignores the fake fork sentinel pid 0' do
      table.record(0)
      expect(table.wait_for(0)).to be_nil
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
  end

  describe '#wait_all' do
    it 'collects every known background job' do
      table.record(9)
      table.record(11)
      system.provide_child(11, 5)
      system.provide_child(9, 4)
      table.wait_all
      expect([table.wait_for(9).exitstatus, table.wait_for(11).exitstatus]).to eq([4, 5])
    end
  end
end
