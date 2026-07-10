# frozen_string_literal: true

RSpec.describe Rush::PipelineRunner do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def echo(*args)
    Rush::AST::SimpleCommand.new([], ['echo', *args].map { |a| Rush::AST::Word.literal(a) }, [])
  end

  describe '#call (parent orchestration)' do
    it 'forks every stage, closes the pipes and returns the last stage status' do
      forked = 0
      allow(system).to receive(:pipe) { [StringIO.new, StringIO.new] }
      allow(system).to receive(:fork) { forked += 1 }
      allow(system).to receive(:waitpid2) { |pid| [pid, status_double(pid)] }
      status = described_class.new(executor, [echo('a'), echo('b'), echo('c')]).call
      expect([forked, status.exitstatus]).to eq([3, 3])
    end

    it 'uses the last stage status unless pipefail is set' do
      stub_wait_statuses(1 => 5, 2 => 0)
      status = described_class.new(executor, [echo('a'), echo('b')]).send(:wait, [1, 2])
      expect(status.exitstatus).to eq(0)
    end

    it 'uses the rightmost non-zero stage status when pipefail is set' do
      state.options.set(:pipefail, true)
      stub_wait_statuses(1 => 5, 2 => 7, 3 => 0)
      status = described_class.new(executor, [echo('a'), echo('b')]).send(:wait, [1, 2, 3])
      expect(status.exitstatus).to eq(7)
    end

    it 'returns success for an all-successful pipefail pipeline' do
      state.options.set(:pipefail, true)
      stub_wait_statuses(1 => 0, 2 => 0)
      status = described_class.new(executor, [echo('a'), echo('b')]).send(:wait, [1, 2])
      expect(status).to be_success
    end

    it 'groups every stage under the first stage leader when job control is on (dash: one group per job)' do
      executor.job_control.enable(system.stderr)
      allow(system).to receive(:pipe) { [StringIO.new, StringIO.new] }
      allow(system).to receive(:fork).and_return(11, 12, 13)
      allow(system).to receive(:waitpid2) { |pid| [pid, status_double(0)] }
      described_class.new(executor, [echo('a'), echo('b'), echo('c')]).call
      expect(system.pgids_set).to eq([[11, 0], [12, 11], [13, 11]])
    end

    it 'opens a pipe per stage boundary and closes every parent end after forking' do
      pipes_made = []
      allow(system).to receive(:pipe) { (pipes_made << [StringIO.new, StringIO.new]).last }
      allow(system).to receive(:fork).and_return(11, 12, 13)
      allow(system).to receive(:waitpid2) { |pid| [pid, status_double(0)] }
      described_class.new(executor, [echo('a'), echo('b'), echo('c')]).call
      expect(pipes_made.size).to eq(2)
      expect(pipes_made.flatten).to all(be_closed)
    end

    def status_double(code)
      instance_double(Process::Status, exitstatus: code, termsig: nil)
    end

    def stub_wait_statuses(codes)
      allow(system).to receive(:waitpid2) { |pid| [pid, status_double(codes.fetch(pid))] }
    end
  end

  describe 'Stage geometry' do
    let(:pipes) { Array.new(2) { [StringIO.new, StringIO.new] } }

    def stage(index)
      Rush::PipelineRunner::Stage.new(index, pipes, 3)
    end

    it 'wires stdin from the previous pipe and stdout to the next' do
      expect([stage(0).input, stage(0).output]).to eq([nil, pipes.fetch(0).last])
      expect([stage(1).input, stage(1).output]).to eq([pipes.fetch(0).first, pipes.fetch(1).last])
      expect([stage(2).input, stage(2).output]).to eq([pipes.fetch(1).first, nil])
    end

    it 'keeps only its own pipe ends' do
      expect(stage(0).ends).to eq([pipes.fetch(0).last])
      expect(stage(1).ends).to eq([pipes.fetch(0).first, pipes.fetch(1).last])
    end

    it 'layers its ends over the base io table, keeping the base elsewhere' do
      base = Rush::IoTable.standard(FakeSystemCalls.new)
      expect([stage(0).io(base).get(0), stage(0).io(base).get(1)]).to eq([base.get(0), pipes.fetch(0).last])
      expect([stage(1).io(base).get(0), stage(1).io(base).get(1)])
        .to eq([pipes.fetch(0).first, pipes.fetch(1).last])
      expect([stage(2).io(base).get(0), stage(2).io(base).get(1)]).to eq([pipes.fetch(1).first, base.get(1)])
    end
  end

  describe '#run_stage (child side)' do
    def runner(stages)
      described_class.new(executor, stages)
    end

    def parse_stage(src)
      Rush::Parser.new(Rush::Lexer.new(src)).parse.entries.first.and_or.commands.first
    end

    def stage(index, pipes)
      Rush::PipelineRunner::Stage.new(index, pipes, 2)
    end

    it 'runs a compound command (not just a simple command) as a stage' do
      pipes = [[StringIO.new, StringIO.new]]
      runner([parse_stage('{ echo a; echo b; }'), echo('x')]).send(:run_stage, stage(0, pipes))
      expect(pipes[0].last.string).to eq("a\nb\n")
    end

    it 'binds the first stage stdout to the first pipe write end' do
      pipes = [[StringIO.new, StringIO.new]]
      runner([echo('a'), echo('b')]).send(:run_stage, stage(0, pipes))
      expect(pipes[0].last.string).to eq("a\n")
    end

    it 'binds the last stage stdout to the shell stdout' do
      runner([echo('a'), echo('b')]).send(:run_stage, stage(1, [[StringIO.new, StringIO.new]]))
      expect(system.stdout.string).to eq("b\n")
    end

    it 'closes the pipe ends the stage does not use' do
      read = StringIO.new
      runner([echo('a'), echo('b')]).send(:run_stage, stage(0, [[read, StringIO.new]]))
      expect(read).to be_closed
    end

    it 'resolves exit inside a stage to its status like a subshell (dash: exit 4 | exit 6 is 6)' do
      status = runner([echo('a'), parse_stage('exit 5')]).send(:run_stage, stage(1, [[StringIO.new, StringIO.new]]))
      expect(status.exitstatus).to eq(5)
    end

    it 'treats loop control inside a stage as inert subshell noise' do
      status = runner([parse_stage('break'), echo('b')]).send(:run_stage, stage(0, [[StringIO.new, StringIO.new]]))
      expect(status).to be_success
    end

    it 'runs an EXIT trap set inside a stage with the stage io' do
      pipes = [[StringIO.new, StringIO.new]]
      runner([parse_stage('{ trap "echo bye" EXIT; :; }'), echo('b')]).send(:run_stage, stage(0, pipes))
      expect(pipes[0].last.string).to eq("bye\n")
    end

    it 'aborts only the stage on a fatal error, with status 2' do
      state.variables.assign('x', '1')
      state.variables.readonly('x')
      status = runner([echo('a'), parse_stage('x=2')]).send(:run_stage, stage(1, [[StringIO.new, StringIO.new]]))
      expect([status.exitstatus, system.stderr.string]).to eq([2, "rush: x: is read only\n"])
    end
  end
end
