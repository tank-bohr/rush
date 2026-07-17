# typed: true
# frozen_string_literal: true

module Rush
  class SystemCalls
    # Resource-limit wrappers for the `ulimit` builtin. The mapping lives outside
    # SystemCalls proper so the impure syscall port stays small as it grows.
    module ResourceLimits
      extend T::Sig

      value = Process.const_get(:RLIMIT_LOCKS) if Process.const_defined?(:RLIMIT_LOCKS)
      locks = T.let(value.is_a?(Integer) ? value : nil, T.nilable(Integer))

      RLIMITS = T.let({
        cpu: Process::RLIMIT_CPU,
        fsize: Process::RLIMIT_FSIZE,
        data: Process::RLIMIT_DATA,
        stack: Process::RLIMIT_STACK,
        core: Process::RLIMIT_CORE,
        rss: Process::RLIMIT_RSS,
        memlock: Process::RLIMIT_MEMLOCK,
        nproc: Process::RLIMIT_NPROC,
        nofile: Process::RLIMIT_NOFILE,
        as: Process::RLIMIT_AS,
        locks: locks,
        rtprio: Process::RLIMIT_RTPRIO
      }.freeze, T::Hash[Symbol, T.nilable(Integer)])

      sig { returns(Integer) }
      def current_umask
        File.umask
      end

      sig { params(mask: Integer).returns(Integer) }
      def change_umask(mask)
        File.umask(mask)
      end

      sig { returns(Integer) }
      def infinity_limit
        Process::RLIM_INFINITY
      end

      sig { params(resource: Symbol).returns([Integer, Integer]) }
      def getrlimit(resource)
        limit = RLIMITS.fetch(resource)
        return [infinity_limit, infinity_limit] unless limit

        Process.getrlimit(limit)
      end

      sig { params(resource: Symbol, soft: Integer, hard: Integer).returns(NilClass) }
      def setrlimit(resource, soft, hard)
        limit = RLIMITS.fetch(resource)
        Kernel.raise Errno::EINVAL unless limit

        Process.setrlimit(T.must(limit), soft, hard)
      end
    end
  end
end
