# typed: true
# frozen_string_literal: true

module Rush
  module Redirection
    # n>&m / n<&m — make fd n a duplicate of fd m by binding it to m's stream
    # (the left-to-right fold means it copies whatever m points at right now),
    # n>&- / n<&- — close fd n. The default fd is 1 for >& and 0 for <&. A target
    # that is neither a number nor `-`, or a number whose fd is not open, is a
    # "bad fd number" — a special-builtin error that aborts the shell with 2.
    class DupRedirect
      extend T::Sig

      sig { params(default_fd: Integer).void }
      def initialize(default_fd)
        @default_fd = default_fd
      end

      sig { params(redirect: AST::Redirect, target: String, io: IoTable, system: SystemCalls).returns(IoTable) }
      def apply(redirect, target, io, system)
        fd = redirect.io_number || @default_fd
        target == '-' ? io.with_closed(fd) : io.with_entry(fd, source(io, target, system))
      end

      private

      # A number whose fd is open duplicates it; a number whose fd is not open
      # (unset, or already closed by an earlier n>&-) is a non-fatal redirect
      # error (status 2, shell continues); a non-number is a special-builtin
      # error (aborts the shell).
      sig { params(io: IoTable, target: String, system: SystemCalls).returns(FdEntry) }
      def source(io, target, system)
        fd = numeric(target)
        entry = io.entry(fd)
        raise RedirectError, "#{target}: fd not open" if entry&.closed?

        return entry if entry

        inherited_entry(system, fd) || raise(RedirectError, "#{target}: fd not open")
      end

      sig { params(system: SystemCalls, fd: Integer).returns(T.nilable(FdEntry)) }
      def inherited_entry(system, fd)
        stream = system.inherited_fd(fd)
        FdEntry.borrowed(stream) if stream
      end

      sig { params(target: String).returns(Integer) }
      def numeric(target)
        Integer(target, 10)
      rescue ArgumentError
        raise BuiltinError, "Bad fd number: #{target}"
      end
    end
  end
end
