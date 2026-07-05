# typed: true
# frozen_string_literal: true

module Rush
  # One binding in the shell's logical fd table. It records the stream currently
  # bound to a descriptor plus ownership: redirections that open files/heredocs
  # are owned and closed after the command, while stdio, pipes and future
  # inherited descriptors are borrowed. A closed entry models `n>&-` / `n<&-`.
  class FdEntry
    extend T::Sig

    sig { params(stream: T.untyped).returns(FdEntry) }
    def self.borrowed(stream)
      new(stream, :borrowed)
    end

    sig { params(stream: T.untyped).returns(FdEntry) }
    def self.owned(stream)
      new(stream, :owned)
    end

    sig { returns(FdEntry) }
    def self.closed
      new(nil, :closed)
    end

    sig { params(stream: T.untyped, state: Symbol).void }
    def initialize(stream, state)
      @stream = stream
      @state = state
    end

    sig { returns(T::Boolean) }
    def owned?
      @state == :owned
    end

    sig { returns(T::Boolean) }
    def closed?
      @state == :closed
    end

    sig { returns(T.untyped) }
    def stream
      raise Errno::EBADF if closed?

      T.must(@stream)
    end

    sig { returns(T.untyped) }
    def to_spawn_option
      closed? ? :close : stream
    end

    sig { params(system: SystemCalls).void }
    def close_redirect(system)
      system.close_redirect(stream) if owned? && !closed?
    end
  end
end
