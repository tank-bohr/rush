# typed: true
# frozen_string_literal: true

module Rush
  class SystemCalls
    # Who the shell process is, mixed into SystemCalls: pids for $$/PPID,
    # effective privileges for the PS1 default, and the invocation name for
    # login-shell detection.
    module ProcessIdentity
      extend T::Sig

      sig { returns(Integer) }
      def pid
        Process.pid
      end

      sig { returns(Integer) }
      def ppid
        Process.ppid
      end

      # Whether the shell runs with root privileges: picks the default PS1
      # ('# ' instead of '$ '), as POSIX permits for privileged users.
      sig { returns(T::Boolean) }
      def privileged?
        Process.euid.zero?
      end

      # How the process was invoked ($0): a leading '-' marks a login shell.
      sig { returns(String) }
      def program_name
        $PROGRAM_NAME
      end
    end
  end
end
