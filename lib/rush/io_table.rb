# typed: true
# frozen_string_literal: true

module Rush
  # Maps file descriptors to IO objects for a single command. Redirections fold
  # over a base table to produce a new one (`with`), so the shell's own streams
  # are never mutated and a command's redirections are scoped to that command.
  class IoTable
    extend T::Sig

    sig { params(streams: T::Hash[Integer, T.untyped]).void }
    def initialize(streams)
      @streams = streams
    end

    sig { params(system: SystemCalls).returns(IoTable) }
    def self.standard(system)
      new(0 => system.stdin, 1 => system.stdout, 2 => system.stderr)
    end

    sig { params(fd: Integer).returns(T.untyped) }
    def get(fd)
      @streams[fd]
    end

    sig { params(fd: Integer, io: T.untyped).returns(IoTable) }
    def with(fd, io)
      self.class.new(@streams.merge(fd => io))
    end

    # The bound streams, for diffing which a command's redirects freshly opened
    # (and so must close) against the base table it inherited.
    sig { returns(T::Array[T.untyped]) }
    def ios
      @streams.values
    end

    # Flush+close the streams this table opened over `base` (the ones a command's
    # redirects added), leaving inherited streams and pipe ends untouched.
    sig { params(base: IoTable, system: SystemCalls).void }
    def close_opened_over(base, system)
      (ios - base.ios).uniq.each { |io| system.close_redirect(io) }
    end

    # A closed fd (ClosedStream) becomes :close so a spawned child closes it.
    sig { returns(T::Hash[Integer, T.untyped]) }
    def to_spawn_options
      @streams.transform_values { |io| io.is_a?(ClosedStream) ? :close : io }
    end
  end
end
