# frozen_string_literal: true

module Rush
  # Runs a multi-stage pipeline: a pipe between each pair of stages, every stage
  # forked (so they run concurrently and never deadlock on a full pipe buffer),
  # the parent's pipe ends closed, then waitpid for all. The pipeline's status is
  # the last stage's. `start_stage` is the one irreducible fork/exit wrapper; the
  # child-side `run_stage` (and its fd setup) is tested directly.
  class PipelineRunner
    def initialize(executor, commands)
      @executor = executor
      @commands = commands
    end

    def call
      pipes = build_pipes
      pids = @commands.each_index.map { |index| start_stage(index, pipes) }
      close_all(pipes)
      wait(pids)
    end

    private

    def build_pipes = Array.new(@commands.size - 1) { @executor.system.pipe }

    def start_stage(index, pipes)
      # :nocov:
      @executor.system.fork { @executor.system.exit!(run_stage(index, pipes).exitstatus) }
      # :nocov:
    end

    def run_stage(index, pipes)
      close_unused(index, pipes)
      CommandRunner.new(@executor, @commands[index], stage_io(index, pipes)).call
    end

    def stage_io(index, pipes)
      io = @executor.io
      io = io.with(0, pipes[index - 1].first) if index.positive?
      last?(index) ? io : io.with(1, pipes[index].last)
    end

    def close_unused(index, pipes)
      keep = stage_ends(index, pipes)
      pipes.flatten.each { |io| io.close unless keep.include?(io) }
    end

    def stage_ends(index, pipes)
      ends = []
      ends << pipes[index - 1].first if index.positive?
      ends << pipes[index].last unless last?(index)
      ends
    end

    def last?(index) = index == @commands.size - 1

    def close_all(pipes) = pipes.flatten.each(&:close)

    def wait(pids)
      pids.map { |pid| Status.of(@executor.system.waitpid2(pid).last) }.last
    end
  end
end
