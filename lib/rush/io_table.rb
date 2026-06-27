# frozen_string_literal: true

module Rush
  # Maps file descriptors to IO objects for a single command. Redirections fold
  # over a base table to produce a new one (`with`), so the shell's own streams
  # are never mutated and a command's redirections are scoped to that command.
  class IoTable
    def initialize(streams)
      @streams = streams
    end

    def self.standard(system)
      new(0 => system.stdin, 1 => system.stdout, 2 => system.stderr)
    end

    def get(fd) = @streams[fd]

    def with(fd, io) = self.class.new(@streams.merge(fd => io))

    def to_spawn_options = @streams.dup
  end
end
