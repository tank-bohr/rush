# frozen_string_literal: true

namespace :docker do
  desc 'Opt-in Docker gate: full native rake plus container-only syscall smoke'
  task :test do
    sh 'bin/test-in-docker'
  end
end
