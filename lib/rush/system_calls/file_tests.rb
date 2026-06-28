# frozen_string_literal: true

module Rush
  class SystemCalls
    # File-test queries for the test/[ builtin (-e -f -d -r -w -x -s -h/-L), mixed
    # into SystemCalls. Thin File delegations, like the rest of the syscall port.
    module FileTests
      def exist?(path)
        File.exist?(path)
      end

      def file?(path)
        File.file?(path)
      end

      def directory?(path)
        File.directory?(path)
      end

      def readable?(path)
        File.readable?(path)
      end

      def writable?(path)
        File.writable?(path)
      end

      def executable?(path)
        File.executable?(path)
      end

      def file_nonempty?(path)
        File.size?(path).to_i.positive?
      end

      def symlink?(path)
        File.symlink?(path)
      end
    end
  end
end
