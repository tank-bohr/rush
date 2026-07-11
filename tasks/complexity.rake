# frozen_string_literal: true

require 'flay'

# Structural-duplication (flay) and complexity (flog) ratchets over
# production code minus the racc-generated parser. Thresholds sit at the
# measured baseline and only go down: new duplication mass or a method past
# the complexity cap fails the build. Both meters measure code, not type
# ceremony: flay hashes the tree with Sorbet sig blocks filtered out, and
# flog caps logic methods while constructors answer to rubocop's AbcSize
# (docs/journal.md, slices 14g/14n/14q).
module ComplexityRake
  module_function

  FILES = (Dir['lib/**/*.rb'] + Dir['exe/*'] - ['lib/rush/parser.rb']).sort.freeze

  # Sorbet `sig` blocks are type declarations, not code: a sig must be a
  # literal block per method, so identical generic sigs are forced and their
  # mass (712 of 906 at filter adoption) only padded the budget real
  # duplication could hide under. flay's own :filters hook drops them from
  # the tree it hashes.
  SORBET_SIG = Sexp::Matcher.parse('(iter (call nil sig) ___)')

  def run(*command)
    IO.popen(command, &:read)
  end

  def sigless_flay
    flay = Flay.new(Flay.default_options.merge(filters: [SORBET_SIG]))
    flay.process(*FILES)
    flay.analyze
    flay
  end

  # The maximum over logic methods: flog sorts descending, so the first
  # per-method line that is not a constructor wins. Wiring constructors
  # measure breadth, not complexity — rubocop's AbcSize caps them at 15 with
  # one documented exception (ShellState) — so skipping them here tightens
  # both gates instead of letting the wiring floor (19.3) pad every other
  # method's budget. The lookahead skips the "flog total" / "flog/method
  # average" header.
  def flog_max(output)
    scores = output.scan(/^\s*(\d+\.\d+): (?!flog)(\S+)/)
    logic = scores.reject { |_score, method| method.end_with?('#initialize') }
    Float(logic.dig(0, 0) || abort('flog printed no method scores'))
  end
end

FLAY_THRESHOLD = 156
FLOG_METHOD_MAX = 16.0

desc "Structural-duplication ratchet (flay, Sorbet sigs filtered; total mass <= #{FLAY_THRESHOLD})"
task :flay do
  flay = ComplexityRake.sigless_flay
  score = flay.total
  flay.report if score > FLAY_THRESHOLD
  puts "flay: total duplication mass #{score} (ratchet #{FLAY_THRESHOLD})"
  abort "flay: #{score} exceeds the ratchet #{FLAY_THRESHOLD} — new structural duplication" if score > FLAY_THRESHOLD
end

desc "Per-method complexity ratchet (flog; logic methods max <= #{FLOG_METHOD_MAX})"
task :flog do
  output = ComplexityRake.run('flog', '--methods-only', *ComplexityRake::FILES)
  max = ComplexityRake.flog_max(output)
  puts output.lines.grep(/^\s*\d+\.\d+: (?!flog)/).grep_v(/#initialize /).first(3).join if max > FLOG_METHOD_MAX
  puts "flog: worst logic method #{max} (ratchet #{FLOG_METHOD_MAX})"
  abort "flog: #{max} exceeds the ratchet #{FLOG_METHOD_MAX} — a method grew past the cap" if max > FLOG_METHOD_MAX
end
