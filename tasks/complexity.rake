# frozen_string_literal: true

# Structural-duplication (flay) and complexity (flog) ratchets over
# production code minus the racc-generated parser. Thresholds sit at the
# measured baseline and only go down: new duplication mass or a method past
# the complexity cap fails the build. The dominant residual flay mass is the
# identical Sorbet generic block sig repeated on the five scoped-state
# helpers — judged idiomatic, not debt: a sig must be a literal block per
# method, so it cannot be extracted (docs/journal.md, slice 14g).
module ComplexityRake
  module_function

  FILES = (Dir['lib/**/*.rb'] + Dir['exe/*'] - ['lib/rush/parser.rb']).freeze

  def run(*command)
    IO.popen(command, &:read)
  end

  def flay_score(output)
    Integer(output[/Total score \(lower is better\) = (\d+)/, 1] || abort('flay printed no total score'))
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

FLAY_THRESHOLD = 906
FLOG_METHOD_MAX = 16.0

desc "Structural-duplication ratchet (flay; total mass <= #{FLAY_THRESHOLD})"
task :flay do
  output = ComplexityRake.run('flay', *ComplexityRake::FILES)
  score = ComplexityRake.flay_score(output)
  puts output if score > FLAY_THRESHOLD
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
