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
  ignore 'lib/rush/ast/param_ref.rb'              # Data.define + self.* methods crashes Steep 2.0.0
  ignore 'lib/rush/expansion/arithmetic/nodes.rb' # Data.define node hierarchy / shared interface
  ignore 'lib/rush/pipeline_runner.rb'            # Data.define + Enumerable-style self calls
  ignore 'lib/rush/system_calls.rb'               # rbs core lacks Process.spawn/exec/fork/exit! on the singleton
  ignore 'lib/rush/parser_support.rb'             # Racc::Parser host methods (do_parse/token_to_str) unmodelled
  ignore 'lib/rush/closed_stream.rb'              # prototype sig: Kernel#raise visibility
  ignore 'lib/rush/builtins/test_expr.rb'         # prototype sig: arg arity
  ignore 'lib/rush/builtins/printf_formatter.rb'  # prototype sig: Hash#fetch overload
  ignore 'lib/rush/builtins/set.rb'               # prototype sig: nilable arg
  ignore 'lib/rush/builtins/kill.rb'              # prototype sig: arg arity
  ignore 'lib/rush/builtins/trap.rb'              # prototype sig: arg arity
  ignore 'lib/rush/expansion/arithmetic/number.rb' # prototype sig: Proc block-pass to untyped block
  ignore 'lib/rush/redirection/registry.rb'       # nested block-param destructuring over heterogeneous hash crashes Steep 2.0.0

  library 'etc', 'forwardable', 'strscan', 'tempfile'

  # Empty `{}` / `[]` / kwargs literals can't be inferred while sig/ is still
  # mostly untyped (prototype bootstrap); this is exactly the noise that the
  # gradual tightening removes. Silenced for now, re-enabled as types land.
  configure_code_diagnostics(Steep::Diagnostic::Ruby.default) do |config|
    config[Steep::Diagnostic::Ruby::UnannotatedEmptyCollection] = nil
  end
end
