# typed: false
# frozen_string_literal: true

module Rush
  class SystemCalls
    # Resource-limit wrappers for the `ulimit` builtin. The mapping lives outside
    # SystemCalls proper so the impure syscall port stays small as it grows.
    module ResourceLimits
      RLIMITS = {
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
        locks: (Process.const_get(:RLIMIT_LOCKS) if Process.const_defined?(:RLIMIT_LOCKS)),
        rtprio: Process::RLIMIT_RTPRIO
      }.freeze

      def current_umask
        File.umask
      end

      def change_umask(mask)
        File.umask(mask)
      end

      def infinity_limit
        Process::RLIM_INFINITY
      end

      def getrlimit(resource)
        limit = RLIMITS.fetch(resource)
        return [infinity_limit, infinity_limit] unless limit

        Process.getrlimit(limit)
      end

      def setrlimit(resource, soft, hard)
        limit = RLIMITS.fetch(resource)
        raise Errno::EINVAL unless limit

        Process.setrlimit(limit, soft, hard)
      end
    end
  end
end
