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

# Sandi Metz limits (100 lines/class, 5 lines/method, 4 params per method),
# enforced via rubocop's Metrics cops.
SANDI_COPS = %w[
  Metrics/MethodLength
  Metrics/ClassLength
  Metrics/ModuleLength
  Metrics/ParameterLists
].freeze

desc 'Sandi Metz limits gate (rubocop Metrics cops)'
task :metrics do
  # Production code only (lib + exe).
  sh "rubocop --only #{SANDI_COPS.join(',')} lib exe"
end

desc 'Code-smell gate (reek; config + rationale in .reek.yml)'
task :reek do
  # Production code only (lib + exe); reek runs as a forward-looking ratchet.
  sh 'reek lib exe'
end

desc 'Full pipeline: compile -> rubocop -> metrics -> reek -> spec (+ coverage gate)'
task default: %i[compile rubocop metrics reek spec]
