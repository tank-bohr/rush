# frozen_string_literal: true

module Rush
  module Redirection
    # Opens the (already-expanded) target file and binds it to the redirection's
    # fd, returning a new IoTable. Covers <, >, >>, <> and >|, which differ only
    # in open mode and default fd.
    class FileRedirect
      def initialize(mode, default_fd)
        @mode = mode
        @default_fd = default_fd
      end

      def apply(redirect, target, io, system)
        io.with(redirect.io_number || @default_fd, system.open_file(target, @mode))
      end
    end
  end
end
