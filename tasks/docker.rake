# frozen_string_literal: true

namespace :docker do
  desc 'Opt-in Docker gate: container specs plus pty/ulimit smokes (RUSH_DOCKER_RAKE_TASK=default for the full gate)'
  task :test do
    sh 'bin/test-in-docker'
  end
end
