# frozen_string_literal: true

# Steep configuration — RBS/Steep is one of two independent type checkers
# (the other is Sorbet); see docs/journal.md "Charter". Signatures live in sig/,
# the implementation in lib/.
#
# Gradual rollout: sig/ is bootstrapped from `rbs prototype` (mostly untyped) and
# tightened slice by slice. Files still carrying prototype-sig errors — plus those
# that hit real ecosystem limits — are listed in IGNORED below with their reason,
# and removed from the list as each is typed for real (tracked in beads rush-211.2).
target :lib do
  signature 'sig'

  check 'lib'

  # --- deferred (each is a follow-up under rush-211.2) ---
  ignore 'lib/rush/parser.rb'                      # racc-generated; not hand-typed
  # Steep attributes instance methods defined inside a `Data.define do...end` block
  # to the *enclosing module*, not the node class, so `value`/`op`/`result` resolve
  # against Arithmetic and fail. Fixing needs the methods moved out of the block
  # into a reopened class (a code restructure decision) — see rush-211.6.
  ignore 'lib/rush/expansion/arithmetic/nodes.rb'
  ignore 'lib/rush/pipeline_runner.rb'            # Data.define Stage block (same instance-method attribution issue) + main class
  ignore 'lib/rush/redirection/registry.rb'       # nested block-param destructuring over heterogeneous hash crashes Steep 2.0.0
  ignore 'lib/rush/expansion/arithmetic/number.rb' # rubocop Style/SymbolProc wants lambda(&:-@)/(&:~), which Steep can't type; no form satisfies both

  library 'etc', 'forwardable', 'strscan', 'tempfile'

  # Empty `{}` / `[]` / kwargs literals can't be inferred while sig/ is still
  # mostly untyped (prototype bootstrap); this is exactly the noise that the
  # gradual tightening removes. Silenced for now, re-enabled as types land.
  configure_code_diagnostics(Steep::Diagnostic::Ruby.default) do |config|
    config[Steep::Diagnostic::Ruby::UnannotatedEmptyCollection] = nil
  end
end
