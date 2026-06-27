# frozen_string_literal: true

GRAMMAR = 'grammar/shell.y'
PARSER = 'lib/rush/parser.rb'
RACC_REPORT = 'lib/rush/parser.output' # where `racc -v` writes, derived from -o
PARSER_REPORT = 'grammar/shell.y.output' # committed next to the grammar (audit)

desc 'Generate the Racc parser from the POSIX §2.10 grammar'
task compile: PARSER

file PARSER => GRAMMAR do
  sh "racc -v -o #{PARSER} #{GRAMMAR}"
  mv RACC_REPORT, PARSER_REPORT
end

desc 'Fail if the committed parser drifts from the grammar'
task check_parser_drift: :compile do
  sh "git diff --exit-code #{PARSER} #{PARSER_REPORT}"
end

CLEAN_PARSER = [PARSER, PARSER_REPORT].freeze
desc 'Remove the generated parser and report'
task :clobber_parser do
  CLEAN_PARSER.each { |f| rm_f f }
end
