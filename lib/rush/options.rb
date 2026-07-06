# typed: true
# frozen_string_literal: true

module Rush
  # The shell options toggled by `set -[+]o name` / `set -[+]x` and friends
  # (:errexit, :nounset, :xtrace, :noglob, :verbose, :pipefail), plus the
  # invocation-only :interactive (-i) and :stdin (-s) flags: the set of those
  # currently on, with #set to flip one, #on? to query it, and #letters to
  # render $-. The letter/name tables live here so the set builtin and
  # Invocation share one vocabulary.
  class Options
    extend T::Sig

    LETTERS = { 'a' => :allexport, 'C' => :noclobber, 'e' => :errexit, 'u' => :nounset,
                'x' => :xtrace, 'f' => :noglob, 'v' => :verbose }.freeze
    LONG = { 'allexport' => :allexport, 'noclobber' => :noclobber,
             'errexit' => :errexit, 'nounset' => :nounset,
             'xtrace' => :xtrace, 'noglob' => :noglob, 'verbose' => :verbose,
             'pipefail' => :pipefail }.freeze
    # $- renders enabled flags in dash's order (its option list, reversed), so
    # differential corpus lines printing $- compare equal against the oracle.
    DASH_ORDER = T.let([[:nounset, 'u'], [:allexport, 'a'], [:noclobber, 'C'], [:verbose, 'v'],
                        [:xtrace, 'x'], [:stdin, 's'], [:interactive, 'i'], [:noglob, 'f'],
                        [:errexit, 'e']].freeze, T::Array[[Symbol, String]])

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
  end
end
