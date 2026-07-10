# typed: true
# frozen_string_literal: true

module Rush
  # Runs a multi-stage pipeline: a pipe between each pair of stages, every stage
  # forked (so they run concurrently and never deadlock on a full pipe buffer),
  # the parent's pipe ends closed, then waitpid for all. The pipeline's status is
  # normally the last stage's, or the rightmost non-zero stage's under pipefail.
  # A stage is an arbitrary command — a simple command, but
  # also a group/subshell/if/while/for/case or a function call — so it is run via
  # the executor with the stage's pipe ends bound as the base IoTable. Each stage
  # is a subshell environment (POSIX 2.12): exit/return end only the stage, loop
  # control is inert, traps reset, and a fatal error aborts just that stage —
  # SubshellRunner#run_body is exactly that resolution, so stages run through it.
  # `start_stage` is the one irreducible fork/exit wrapper; the child-side
  # `run_stage` (and its fd setup) is tested directly.
  class PipelineRunner
    extend T::Sig

    # One stage of the pipeline: its position plus the shared pipe array and the
    # stage count. The fd topology — which pipe end feeds this stage (input) and
    # which it feeds (output), and so which ends to keep open (ends) — derives
    # from all three, so the runner threads a single Stage rather than the
    # (index, pipes) pair through every per-stage step.
    class Stage
      extend T::Sig

      sig { returns(Integer) }
      attr_reader :index, :count

      sig { returns(T::Array[[IO, IO]]) }
      attr_reader :pipes

      sig { params(index: Integer, pipes: T::Array[[IO, IO]], count: Integer).void }
      def initialize(index, pipes, count)
        @index = index
        @pipes = pipes
        @count = count
      end

      sig { returns(T::Boolean) }
      def last?
        index == count - 1
      end

      sig { returns(T.nilable(IO)) }
      def input
        index.positive? ? pipes.fetch(index - 1).first : nil
      end

      sig { returns(T.nilable(IO)) }
      def output
        last? ? nil : pipes.fetch(index).last
      end

      sig { returns(T::Array[IO]) }
      def ends
        [input, output].compact
      end

      # Layer this stage's pipe ends over the base IoTable: stdin from the
      # previous pipe (unless first), stdout to the next pipe (unless last).
      sig { params(base: IoTable).returns(IoTable) }
      def io(base)
        base = base.with(0, input) if input
        output ? base.with(1, output) : base
      end

      sig { void }
      def close_unused
        keep = ends
        pipes.each { |pipe| close_unkept(pipe, keep) }
      end

      private

      sig { params(pipe: [IO, IO], keep: T::Array[IO]).void }
      def close_unkept(pipe, keep)
        pipe.each { |io| io.close unless keep.include?(io) }
      end
    end

    sig { params(executor: Executor, commands: T::Array[AST::Node]).void }
    def initialize(executor, commands)
      @executor = executor
      @commands = commands
    end

    sig { returns(Status) }
    def call
      pipes = build_pipes
      pids = start_stages(pipes)
      close_all(pipes)
      wait(pids)
    end

    private

    sig { returns(T::Array[[IO, IO]]) }
    def build_pipes
      Array.new(@commands.size - 1) { @executor.system.pipe }
    end

    # Stages fork sequentially, each joining the first stage's process group
    # under job control (dash: one group per pipeline, first process is the
    # leader). Because stage 0's group is settled — parent-side setpgid —
    # before stage 1 is even forked, later members can never race the group
    # into existence.
    sig { params(pipes: T::Array[[IO, IO]]).returns(T::Array[Integer]) }
    def start_stages(pipes)
      @commands.each_index.with_object([]) do |index, pids|
        pids << start_stage(Stage.new(index, pipes, @commands.size), pids.first)
      end
    end

    sig { params(stage: Stage, leader: T.nilable(Integer)).returns(Integer) }
    def start_stage(stage, leader)
      @executor.job_control.launch(leader: leader) { @executor.system.exit!(run_stage(stage).exitstatus) }
    end

    sig { params(stage: Stage).returns(Status) }
    def run_stage(stage)
      close_unused(stage)
      body = @commands.fetch(stage.index)
      @executor.with_io(stage.io(@executor.io)) { SubshellRunner.new(@executor, body).run_body }
    end

    sig { params(stage: Stage).void }
    def close_unused(stage)
      stage.close_unused
    end

    sig { params(pipes: T::Array[[IO, IO]]).void }
    def close_all(pipes)
      pipes.each { |pipe| pipe.each(&:close) }
    end

    sig { params(pids: T::Array[Integer]).returns(Status) }
    def wait(pids)
      statuses = PipelineStatuses.new(pids.map { |pid| wait_status(pid) })
      pipefail? ? statuses.pipefail : statuses.last_stage
    end

    sig { params(pid: Integer).returns(Status) }
    def wait_status(pid)
      @executor.jobs.await(pid)
    end

    sig { returns(T::Boolean) }
    def pipefail?
      @executor.state.options.on?(:pipefail)
    end
  end
end
