# frozen_string_literal: true

module Rush
  # Runs a multi-stage pipeline: a pipe between each pair of stages, every stage
  # forked (so they run concurrently and never deadlock on a full pipe buffer),
  # the parent's pipe ends closed, then waitpid for all. The pipeline's status is
  # the last stage's. A stage is an arbitrary command — a simple command, but
  # also a group/subshell/if/while/for/case or a function call — so it is run via
  # the executor with the stage's pipe ends bound as the base IoTable.
  # `start_stage` is the one irreducible fork/exit wrapper; the child-side
  # `run_stage` (and its fd setup) is tested directly.
  class PipelineRunner
    # One stage of the pipeline: its position plus the shared pipe array and the
    # stage count. The fd topology — which pipe end feeds this stage (input) and
    # which it feeds (output), and so which ends to keep open (ends) — derives
    # from all three, so the runner threads a single Stage rather than the
    # (index, pipes) pair through every per-stage step.
    Stage = Data.define(:index, :pipes, :count) do
      def last? = index == count - 1
      def input = index.positive? ? pipes[index - 1].first : nil
      def output = last? ? nil : pipes[index].last
      def ends = [input, output].compact

      # Layer this stage's pipe ends over the base IoTable: stdin from the
      # previous pipe (unless first), stdout to the next pipe (unless last).
      def io(base)
        base = base.with(0, input) if input
        output ? base.with(1, output) : base
      end
    end

    def initialize(executor, commands)
      @executor = executor
      @commands = commands
    end

    def call
      pipes = build_pipes
      pids = @commands.each_index.map { |index| start_stage(Stage.new(index, pipes, @commands.size)) }
      close_all(pipes)
      wait(pids)
    end

    private

    def build_pipes = Array.new(@commands.size - 1) { @executor.system.pipe }

    def start_stage(stage)
      # :nocov:
      @executor.system.fork { @executor.system.exit!(run_stage(stage).exitstatus) }
      # :nocov:
    end

    def run_stage(stage)
      close_unused(stage)
      @executor.with_io(stage.io(@executor.io)) { @executor.run(@commands[stage.index]) }
    end

    def close_unused(stage)
      keep = stage.ends
      stage.pipes.flatten.each { |io| io.close unless keep.include?(io) }
    end

    def close_all(pipes) = pipes.flatten.each(&:close)

    def wait(pids)
      pids.map { |pid| Status.of(@executor.system.waitpid2(pid).last) }.last
    end
  end
end
