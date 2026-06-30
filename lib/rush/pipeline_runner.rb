# typed: true
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
    extend T::Sig

    Stage = Data.define(:index, :pipes, :count)
    # One stage of the pipeline: its position plus the shared pipe array and the
    # stage count. The fd topology — which pipe end feeds this stage (input) and
    # which it feeds (output), and so which ends to keep open (ends) — derives
    # from all three, so the runner threads a single Stage rather than the
    # (index, pipes) pair through every per-stage step. Its methods live in a
    # reopened class (assignment form, not `class < Data.define` and not the
    # define block) — the one Data shape both Steep and Sorbet accept.
    class Stage
      extend T::Sig

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
    end

    sig { params(executor: Executor, commands: T::Array[AST::Node]).void }
    def initialize(executor, commands)
      @executor = executor
      @commands = commands
    end

    sig { returns(Status) }
    def call
      pipes = build_pipes
      pids = @commands.each_index.map { |index| start_stage(Stage.new(index, pipes, @commands.size)) }
      close_all(pipes)
      wait(pids)
    end

    private

    sig { returns(T::Array[[IO, IO]]) }
    def build_pipes
      Array.new(@commands.size - 1) { @executor.system.pipe }
    end

    sig { params(stage: Stage).returns(T.nilable(Integer)) }
    def start_stage(stage)
      # :nocov:
      @executor.system.fork { @executor.system.exit!(run_stage(stage).exitstatus) }
      # :nocov:
    end

    sig { params(stage: Stage).returns(Status) }
    def run_stage(stage)
      close_unused(stage)
      @executor.with_io(stage.io(@executor.io)) { @executor.run(@commands.fetch(stage.index)) }
    end

    sig { params(stage: Stage).void }
    def close_unused(stage)
      keep = stage.ends
      stage.pipes.flatten.each { |io| io.close unless keep.include?(io) }
    end

    sig { params(pipes: T::Array[[IO, IO]]).void }
    def close_all(pipes)
      pipes.flatten.each(&:close)
    end

    sig { params(pids: T::Array[T.nilable(Integer)]).returns(Status) }
    def wait(pids)
      # fork returns the child pid in the parent (nil only in the child, which
      # exit!s and never reaches here), so compact only quiets the nominal
      # Integer?; a pipeline always has >= 2 stages, so fetch(-1) has a status.
      pids.compact.map { |pid| Status.of(@executor.system.waitpid2(pid).last) }.fetch(-1)
    end
  end
end
