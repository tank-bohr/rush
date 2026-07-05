# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `cd [dir]` — change the working directory, maintaining a *logical* PWD
    # (not Dir.pwd, which resolves symlinks) plus OLDPWD. Defaults to $HOME.
    class Cd < Base
      extend T::Sig

      # A CDPATH resolution result: the path to chdir to, and whether POSIX
      # requires printing the resolved logical directory after a successful cd.
      Target = Data.define(:path, :echo)

      sig { returns(Status) }
      def call
        target = operands.first || executor.state.variables.get('HOME')
        return report('HOME not set') unless target

        target == '-' ? change_back : change_to(target)
      end

      private

      sig { params(dir: String).returns(Status) }
      def change_to(dir)
        target = resolve_cdpath(dir)
        perform_chdir(target.path)
        success_after_cdpath(target)
      rescue Errno::ENOENT, Errno::ENOTDIR
        report("#{dir}: No such file or directory")
      end

      sig { returns(Status) }
      def change_back
        dir = oldpwd
        perform_chdir(dir)
        success_with_echo
      rescue Errno::ENOENT, Errno::ENOTDIR
        report("#{dir}: No such file or directory")
      end

      sig { returns(String) }
      def oldpwd
        executor.state.variables.get('OLDPWD') || executor.state.variables.current_pwd
      end

      sig { params(dir: String).returns(Target) }
      def resolve_cdpath(dir)
        return Target.new(path: dir, echo: false) unless search_cdpath?(dir)

        cdpath_targets(dir).find { |target| executor.system.directory?(target.path) } ||
          Target.new(path: dir, echo: false)
      end

      sig { params(dir: String).returns(T::Boolean) }
      def search_cdpath?(dir)
        cdpath? && relative_cdpath_operand?(dir)
      end

      sig { params(dir: String).returns(T::Boolean) }
      def relative_cdpath_operand?(dir)
        !dir.start_with?('/') && !%w[. ..].include?(dir.split('/', 2).first)
      end

      sig { returns(T::Boolean) }
      def cdpath?
        !!executor.state.variables.get('CDPATH')
      end

      sig { params(dir: String).returns(T::Array[Target]) }
      def cdpath_targets(dir)
        cdpath_entries.map { |prefix| cdpath_target(prefix, dir) }
      end

      sig { returns(T::Array[String]) }
      def cdpath_entries
        T.must(executor.state.variables.get('CDPATH')).split(':', -1)
      end

      sig { params(prefix: String, dir: String).returns(Target) }
      def cdpath_target(prefix, dir)
        Target.new(path: cdpath_path(prefix, dir), echo: cdpath_echo?(prefix))
      end

      sig { params(prefix: String, dir: String).returns(String) }
      def cdpath_path(prefix, dir)
        prefix.empty? ? dir : "#{prefix}/#{dir}"
      end

      sig { params(prefix: String).returns(T::Boolean) }
      def cdpath_echo?(prefix)
        !prefix.empty?
      end

      sig { params(dir: String).void }
      def perform_chdir(dir)
        executor.system.chdir(dir)
        update_pwd(dir)
      end

      sig { returns(Status) }
      def success_with_echo
        stdout.puts(executor.state.variables.current_pwd)
        success
      end

      sig { params(target: Target).returns(Status) }
      def success_after_cdpath(target)
        target.echo ? success_with_echo : success
      end

      sig { params(dir: String).void }
      def update_pwd(dir)
        variables = executor.state.variables
        variables.move_to(executor.system.expand_path(dir, variables.current_pwd))
      end

      sig { params(message: String).returns(Status) }
      def report(message)
        stderr.puts("rush: cd: #{message}")
        failure
      end
    end
  end
end
