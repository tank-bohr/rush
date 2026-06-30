# typed: true
# frozen_string_literal: true

module Rush
  module Redirection
    # Opens the (already-expanded) target file and binds it to the redirection's
    # fd, returning a new IoTable. Covers <, >, >>, <> and >|, which differ only
    # in open mode and default fd.
    class FileRedirect
      extend T::Sig

      sig { params(mode: T.untyped, default_fd: T.untyped).void }
      def initialize(mode, default_fd)
        @mode = mode
        @default_fd = default_fd
      end

      # A failure to open the target (missing directory, permission denied, a
      # directory where a file is expected) is a redirection error: the command
      # is left unrun with status 2 (RedirectError), or — on a special builtin —
      # aborts the shell, the escalation being handled one level up in
      # CommandRunner where the command word is known.
      sig { params(redirect: T.untyped, target: T.untyped, io: T.untyped, system: T.untyped).returns(T.untyped) }
      def apply(redirect, target, io, system)
        io.with(redirect.io_number || @default_fd, system.open_file(target, @mode))
      rescue SystemCallError
        raise RedirectError, "#{target}: cannot redirect"
      end
    end
  end
end
