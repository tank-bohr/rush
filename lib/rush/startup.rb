# typed: true
# frozen_string_literal: true

module Rush
  # The startup files a session runs before its main input, per the dash
  # oracle (POSIX defines ENV and leaves login files unspecified): a login
  # shell runs /etc/profile then $HOME/.profile; an interactive shell then
  # runs the file named by ENV, its value subjected to parameter expansion
  # only. Missing or unreadable files are skipped silently; errors inside a
  # file follow the session's normal policy (a batch shell aborts, an
  # interactive one reports and carries on); `return` is bounded to its file
  # like a dot script, leaving its code in $?.
  class Startup
    extend T::Sig

    PROFILE = '/etc/profile'

    sig { params(login: T::Boolean, interactive: T::Boolean).void }
    def initialize(login:, interactive:)
      @login = login
      @interactive = interactive
    end

    sig { params(executor: Executor).void }
    def run(executor)
      paths(executor).each { |path| source(executor, path) }
    end

    private

    sig { params(executor: Executor).returns(T::Array[String]) }
    def paths(executor)
      paths = @login ? [PROFILE, home_profile(executor)] : [] #: Array[String?]
      paths << env_file(executor) if @interactive
      paths.compact
    end

    sig { params(executor: Executor).returns(T.nilable(String)) }
    def home_profile(executor)
      home = executor.state.variables.get('HOME').to_s
      return if home.empty?

      "#{home}/.profile"
    end

    # The ENV pathname, parameter-expanded (POSIX); nil when unset or empty.
    sig { params(executor: Executor).returns(T.nilable(String)) }
    def env_file(executor)
      raw = executor.state.variables.get('ENV').to_s
      return if raw.empty?

      executor.expander.expand_value(ParamText.new(raw).word, tilde: :none)
    end

    sig { params(executor: Executor, path: String).void }
    def source(executor, path)
      text = read(executor, path)
      run_file(executor, text) if text
    end

    sig { params(executor: Executor, path: String).returns(T.nilable(String)) }
    def read(executor, path)
      executor.system.read_file(path)
    rescue SystemCallError
      nil
    end

    sig { params(executor: Executor, text: String).void }
    def run_file(executor, text)
      SourceRunner.new(executor, text).run
    rescue ReturnSignal => e
      executor.state.record_status(Status.new(e.code))
    end
  end
end
