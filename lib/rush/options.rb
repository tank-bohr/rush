# typed: true
# frozen_string_literal: true

module Rush
  # The shell options toggled by `set -[+]o name` / `set -[+]x` and friends
  # (:errexit, :nounset, :xtrace, :noglob, :verbose, :pipefail), plus the
  # invocation-only :interactive (-i) and :stdin (-s) flags: the set of those
  # currently on, with #set to flip one, #on? to query it, #letters to
  # render $-, and the bare `set -o`/`set +o` listings. The letter/name
  # tables live here so the set builtin and Invocation share one vocabulary.
  class Options
    extend T::Sig

    LETTERS = { 'a' => :allexport, 'C' => :noclobber, 'e' => :errexit, 'u' => :nounset,
                'x' => :xtrace, 'f' => :noglob, 'v' => :verbose, 'm' => :monitor }.freeze
    # Every long name in dash's listing order — the bare `set -o`/`set +o`
    # output shows the invocation-only flags too, like dash does.
    NAMES = { 'errexit' => :errexit, 'noglob' => :noglob, 'interactive' => :interactive,
              'monitor' => :monitor, 'stdin' => :stdin, 'xtrace' => :xtrace,
              'verbose' => :verbose, 'noclobber' => :noclobber, 'allexport' => :allexport,
              'nounset' => :nounset, 'pipefail' => :pipefail }.freeze
    # The names `set -o name` accepts: everything listable minus the flags
    # only invocation can set.
    LONG = NAMES.except('interactive', 'stdin').freeze
    # $- renders enabled flags in dash's order (its option list, reversed), so
    # differential corpus lines printing $- compare equal against the oracle.
    DASH_ORDER = T.let([[:nounset, 'u'], [:allexport, 'a'], [:noclobber, 'C'], [:verbose, 'v'],
                        [:xtrace, 'x'], [:stdin, 's'], [:monitor, 'm'], [:interactive, 'i'],
                        [:noglob, 'f'], [:errexit, 'e']].freeze, T::Array[[Symbol, String]])

    sig { void }
    def initialize
      @enabled = Set.new
    end

    sig { params(name: Symbol, enabled: T::Boolean).void }
    def set(name, enabled)
      enabled ? @enabled.add(name) : @enabled.delete(name)
    end

    sig { params(name: Symbol).returns(T::Boolean) }
    def on?(name)
      @enabled.include?(name)
    end

    # The current option flags as the $- special parameter renders them.
    sig { returns(String) }
    def letters
      DASH_ORDER.filter_map { |option, letter| letter if on?(option) }.join
    end

    # The bare `set -o` table rows in dash's format: the name padded to 16
    # columns, then on/off.
    sig { returns(T::Array[String]) }
    def settings_rows
      render_settings('%<name>-16son', '%<name>-16soff')
    end

    # The bare `set +o` output: `set -o name` / `set +o name` lines that
    # reproduce the current settings when re-input (POSIX XCU set).
    sig { returns(T::Array[String]) }
    def reinput_lines
      render_settings('set -o %<name>s', 'set +o %<name>s')
    end

    private

    # One rendered line per long option name: the on form when the option is
    # enabled, the off form otherwise.
    sig { params(on_form: String, off_form: String).returns(T::Array[String]) }
    def render_settings(on_form, off_form)
      NAMES.map { |name, option| format(on?(option) ? on_form : off_form, name: name) }
    end
  end
end
