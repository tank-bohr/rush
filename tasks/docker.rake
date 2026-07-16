# frozen_string_literal: true

namespace :docker do
  desc 'Opt-in Docker gate: specs plus ABI/pty/ulimit smokes (RUSH_DOCKER_RAKE_TASK=default for full gate)'
  task :test do
    sh 'bin/test-in-docker'
  end
end
