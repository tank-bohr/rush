# frozen_string_literal: true

RSpec.describe Rush::PipelineRunner do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def echo(*args) = Rush::AST::SimpleCommand.new([], ['echo', *args].map { |a| Rush::AST::Word.literal(a) }, [])

  describe '#call (parent orchestration)' do
    it 'forks every stage, closes the pipes and returns the last stage status' do
      forked = 0
      allow(system).to receive(:pipe) { [StringIO.new, StringIO.new] }
      allow(system).to receive(:fork) { forked += 1 }
      allow(system).to receive(:waitpid2) { |pid| [pid, status_double(pid)] }
      status = described_class.new(executor, [echo('a'), echo('b'), echo('c')]).call
      expect([forked, status.exitstatus]).to eq([3, 3])
    end

    def status_double(code) = instance_double(Process::Status, exitstatus: code, termsig: nil)
  end

  describe '#run_stage (child side)' do
    def runner(stages) = described_class.new(executor, stages)
    def parse_stage(src) = Rush::Parser.new(Rush::Lexer.new(src)).parse.entries.first.and_or.commands.first

    it 'runs a compound command (not just a simple command) as a stage' do
      pipes = [[StringIO.new, StringIO.new]]
      runner([parse_stage('{ echo a; echo b; }'), echo('x')]).send(:run_stage, 0, pipes)
      expect(pipes[0].last.string).to eq("a\nb\n")
    end

    it 'binds the first stage stdout to the first pipe write end' do
      pipes = [[StringIO.new, StringIO.new]]
      runner([echo('a'), echo('b')]).send(:run_stage, 0, pipes)
      expect(pipes[0].last.string).to eq("a\n")
    end

    it 'binds the last stage stdout to the shell stdout' do
      runner([echo('a'), echo('b')]).send(:run_stage, 1, [[StringIO.new, StringIO.new]])
      expect(system.stdout.string).to eq("b\n")
    end

    it 'closes the pipe ends the stage does not use' do
      read = StringIO.new
      runner([echo('a'), echo('b')]).send(:run_stage, 0, [[read, StringIO.new]])
      expect(read).to be_closed
    end
  end
end
