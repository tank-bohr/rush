# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

load 'tasks/compile.rake'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

# Generated parser must exist before linting or testing.
task spec: :compile
task rubocop: :compile

desc 'Code-smell gate (reek; config + rationale in .reek.yml)'
task :reek do
  # Production code only (lib + exe); reek runs as a forward-looking ratchet.
  sh 'reek lib exe'
end

desc 'Type-check gate (Steep over RBS sigs in sig/; config + rollout in Steepfile)'
task :steep do
  # RBS/Steep is one of two independent type checkers (see docs/journal.md).
  sh 'steep check'
end

desc 'Full pipeline: compile -> rubocop -> reek -> steep -> spec (+ coverage gate)'
task default: %i[compile rubocop reek steep spec]
