# typed: true
# frozen_string_literal: true

module Rush
  module Redirection
    # Opens the (already-expanded) target file and binds it to the redirection's
    # fd, returning a new IoTable. Covers <, >, >>, <> and >|, which differ only
    # in open mode and default fd.
    class FileRedirect
      extend T::Sig

      EXCLUSIVE = T.let(File::WRONLY | File::CREAT | File::EXCL, Integer)

      sig do
        params(mode: T.any(String, Integer), default_fd: Integer,
               options: T.nilable(Options), protection: T.nilable(Symbol)).void
      end
      def initialize(mode, default_fd, options: nil, protection: nil)
        @mode = mode
        @default_fd = default_fd
        @options = options
        @protection = protection
      end

      # A failure to open the target (missing directory, permission denied, a
      # directory where a file is expected) is a redirection error: the command
      # is left unrun with status 2 (RedirectError), or — on a special builtin —
      # aborts the shell, the escalation being handled one level up in
      # CommandRunner where the command word is known.
      sig { params(redirect: AST::Redirect, target: String, io: IoTable, system: SystemCalls).returns(IoTable) }
      def apply(redirect, target, io, system)
        io.with_owned(redirect.io_number || @default_fd, system.open_file(target, open_mode))
      rescue SystemCallError
        raise RedirectError, "#{target}: cannot redirect"
      end

      private

      sig { returns(T.any(String, Integer)) }
      def open_mode
        noclobber? ? EXCLUSIVE : @mode
      end

      sig { returns(T::Boolean) }
      def noclobber?
        @protection == :noclobber && @options&.on?(:noclobber) == true
      end
    end
  end
end
