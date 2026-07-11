# typed: true
# frozen_string_literal: true

module Rush
  class SystemCalls
    # File-test queries for the test/[ builtin (-e -f -d -r -w -x -s -h/-L,
    # the file types -p -b -c -S, the mode bits -g -u, and the fd probe -t),
    # mixed into SystemCalls. Thin File/IO delegations, like the rest of the
    # syscall port.
    module FileTests
      extend T::Sig

      sig { params(path: String).returns(T::Boolean) }
      def exist?(path)
        File.exist?(path)
      end

      sig { params(path: String).returns(T::Boolean) }
      def file?(path)
        File.file?(path)
      end

      sig { params(path: String).returns(T::Boolean) }
      def directory?(path)
        File.directory?(path)
      end

      sig { params(path: String).returns(T::Boolean) }
      def readable?(path)
        File.readable?(path)
      end

      sig { params(path: String).returns(T::Boolean) }
      def writable?(path)
        # !! because Sorbet's stdlib RBI types File.writable? as T.nilable(Integer)
        # (it returns a real Boolean at runtime, like the other File predicates here).
        !!File.writable?(path)
      end

      sig { params(path: String).returns(T::Boolean) }
      def executable?(path)
        File.executable?(path)
      end

      sig { params(path: String).returns(T::Boolean) }
      def file_nonempty?(path)
        File.size?(path).to_i.positive?
      end

      sig { params(path: String).returns(T::Boolean) }
      def symlink?(path)
        File.symlink?(path)
      end

      sig { params(path: String).returns(T::Boolean) }
      def pipe?(path)
        File.pipe?(path)
      end

      sig { params(path: String).returns(T::Boolean) }
      def blockdev?(path)
        File.blockdev?(path)
      end

      sig { params(path: String).returns(T::Boolean) }
      def chardev?(path)
        File.chardev?(path)
      end

      sig { params(path: String).returns(T::Boolean) }
      def socket?(path)
        File.socket?(path)
      end

      sig { params(path: String).returns(T::Boolean) }
      def setgid?(path)
        File.setgid?(path)
      end

      sig { params(path: String).returns(T::Boolean) }
      def setuid?(path)
        File.setuid?(path)
      end

      # isatty(fd) for test -t: any unusable descriptor number (closed, huge,
      # negative) is simply not a terminal, as in dash.
      sig { params(fd: Integer).returns(T::Boolean) }
      def tty_fd?(fd)
        IO.new(fd, autoclose: false).tty?
      rescue ArgumentError, RangeError, SystemCallError
        false
      end
    end
  end
end
