# typed: true
# frozen_string_literal: true

module Rush
  # Maps file descriptors to fd entries for a single command. Redirections fold
  # over a base table to produce a new one (`with`), so the shell's own streams
  # are never mutated and a command's redirections are scoped to that command.
  class IoTable
    extend T::Sig

    sig { params(entries: T::Hash[Integer, T.untyped]).void }
    def initialize(entries)
      @entries = entries.transform_values { |entry| fd_entry(entry) }
    end

    sig { params(system: SystemCalls).returns(IoTable) }
    def self.standard(system)
      new(0 => FdEntry.borrowed(system.stdin),
          1 => FdEntry.borrowed(system.stdout),
          2 => FdEntry.borrowed(system.stderr))
    end

    sig { params(fd: Integer).returns(T.untyped) }
    def get(fd)
      entry(fd)&.stream
    end

    sig { params(fd: Integer).returns(T.nilable(FdEntry)) }
    def entry(fd)
      @entries.fetch(fd, nil)
    end

    sig { params(fd: Integer, io: T.untyped).returns(IoTable) }
    def with(fd, io)
      with_entry(fd, FdEntry.borrowed(io))
    end

    sig { params(fd: Integer, io: T.untyped).returns(IoTable) }
    def with_owned(fd, io)
      with_entry(fd, FdEntry.owned(io))
    end

    sig { params(fd: Integer).returns(IoTable) }
    def with_closed(fd)
      with_entry(fd, FdEntry.closed)
    end

    sig { params(fd: Integer, entry: FdEntry).returns(IoTable) }
    def with_entry(fd, entry)
      self.class.new(@entries.merge(fd => entry))
    end

    # The bound entries, for diffing which redirections freshly opened owned
    # streams over the base table. Borrowed entries (stdio, pipes and inherited
    # fds) are intentionally not closed by redirect cleanup.
    sig { returns(T::Array[FdEntry]) }
    def entries
      @entries.values
    end

    # Flush+close the streams this table opened over `base` (the ones a command's
    # redirects added), leaving inherited streams and pipe ends untouched.
    sig { params(base: IoTable, system: SystemCalls).void }
    def close_opened_over(base, system)
      (entries - base.entries).uniq.each { |entry| entry.close_redirect(system) }
    end

    # A closed fd becomes :close so a spawned child closes it.
    sig { returns(T::Hash[Integer, T.untyped]) }
    def to_spawn_options
      @entries.transform_values(&:to_spawn_option)
    end

    private

    sig { params(entry: T.untyped).returns(FdEntry) }
    def fd_entry(entry)
      entry.is_a?(FdEntry) ? entry : FdEntry.borrowed(entry)
    end
  end
end
