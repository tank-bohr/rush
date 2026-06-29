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

  library 'etc', 'forwardable', 'strscan', 'tempfile'

  # Empty `{}` / `[]` / kwargs literals can't be inferred while sig/ is still
  # mostly untyped (prototype bootstrap); this is exactly the noise that the
  # gradual tightening removes. Silenced for now, re-enabled as types land.
  configure_code_diagnostics(Steep::Diagnostic::Ruby.default) do |config|
    config[Steep::Diagnostic::Ruby::UnannotatedEmptyCollection] = nil
  end
end
