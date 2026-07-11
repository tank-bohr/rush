# frozen_string_literal: true

# Structural-duplication (flay) and complexity (flog) ratchets over
# production code minus the racc-generated parser. Thresholds sit at the
# measured baseline and only go down: new duplication mass or a method past
# the complexity cap fails the build. The known flay debt — the seven-node
# save/yield/restore cluster — is filed in beads; paying it lowers the
# threshold with it.
module ComplexityRake
  module_function

  FILES = (Dir['lib/**/*.rb'] + Dir['exe/*'] - ['lib/rush/parser.rb']).freeze

  def run(*command)
    IO.popen(command, &:read)
  end

  def flay_score(output)
    Integer(output[/Total score \(lower is better\) = (\d+)/, 1] || abort('flay printed no total score'))
  end

  # First per-method line; flog sorts descending, so it is the maximum.
  # The lookahead skips the "flog total" / "flog/method average" header.
  def flog_max(output)
    Float(output[/^\s*(\d+\.\d+): (?!flog)/, 1] || abort('flog printed no method scores'))
  end
end

FLAY_THRESHOLD = 2016
FLOG_METHOD_MAX = 26.0

desc "Structural-duplication ratchet (flay; total mass <= #{FLAY_THRESHOLD})"
task :flay do
  output = ComplexityRake.run('flay', *ComplexityRake::FILES)
  score = ComplexityRake.flay_score(output)
  puts output if score > FLAY_THRESHOLD
  puts "flay: total duplication mass #{score} (ratchet #{FLAY_THRESHOLD})"
  abort "flay: #{score} exceeds the ratchet #{FLAY_THRESHOLD} — new structural duplication" if score > FLAY_THRESHOLD
end

desc "Per-method complexity ratchet (flog; max <= #{FLOG_METHOD_MAX})"
task :flog do
  output = ComplexityRake.run('flog', '--methods-only', *ComplexityRake::FILES)
  max = ComplexityRake.flog_max(output)
  puts output.lines.grep(/^\s*\d+\.\d+: (?!flog)/).first(3).join if max > FLOG_METHOD_MAX
  puts "flog: worst method #{max} (ratchet #{FLOG_METHOD_MAX})"
  abort "flog: #{max} exceeds the ratchet #{FLOG_METHOD_MAX} — a method grew past the cap" if max > FLOG_METHOD_MAX
end
