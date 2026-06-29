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
      def initialize(default_fd)
        @default_fd = default_fd
      end

      def apply(redirect, target, io, _system)
        fd = redirect.io_number || @default_fd
        io.with(fd, target == '-' ? ClosedStream.new : source(io, target))
      end

      private

      # A number whose fd is open duplicates it; a number whose fd is not open
      # (unset, or already closed by an earlier n>&-) is a non-fatal redirect
      # error (status 2, shell continues); a non-number is a special-builtin
      # error (aborts the shell).
      def source(io, target)
        stream = io.get(numeric(target))
        raise RedirectError, "#{target}: fd not open" if !stream || stream.is_a?(ClosedStream)

        stream
      end

      def numeric(target)
        Integer(target, 10)
      rescue ArgumentError
        raise BuiltinError, "Bad fd number: #{target}"
      end
    end
  end
end
