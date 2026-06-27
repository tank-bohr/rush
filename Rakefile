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

# Sandi Metz limits: 100 lines/class, 5 lines/method, 4 params per method.
# These mirror the sandi_meter thresholds 1:1. sandi_meter itself (2015, Ripper-
# based) is unmaintained: it calls the removed File.exists? and miscounts modern
# Ruby (endless methods → 0 classes/methods) on Ruby >= 3.2, so it cannot gate.
# The plan's documented fallback is used instead: rubocop's Metrics cops.
SANDI_COPS = %w[
  Metrics/MethodLength
  Metrics/ClassLength
  Metrics/ModuleLength
  Metrics/ParameterLists
].freeze

desc 'Sandi Metz limits gate (rubocop fallback; sandi_meter is broken on Ruby >= 3.2)'
task :metrics do
  # Production code only (lib + exe), mirroring the plan's `sandi_meter -p lib/`.
  sh "rubocop --only #{SANDI_COPS.join(',')} lib exe"
end

desc 'Full pipeline: compile -> rubocop -> metrics -> spec (+ coverage gate)'
task default: %i[compile rubocop metrics spec]
