# typed: true
# frozen_string_literal: true

module Rush
  class SystemCalls
    # File-test queries for the test/[ builtin (-e -f -d -r -w -x -s -h/-L), mixed
    # into SystemCalls. Thin File delegations, like the rest of the syscall port.
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
    end
  end
end
