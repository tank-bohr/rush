# typed: true
# frozen_string_literal: true

# Data readers and positional constructor generated outside Sorbet's view.
# This mirrors the independent public RBS declaration.
module Rush
  # Original shell and parent process ids used for $$ and PPID.
  class ShellProcessIds < Data
    extend T::Sig

    sig { returns(Integer) }
    attr_reader :shell

    sig { returns(Integer) }
    attr_reader :parent

    sig { params(shell: Integer, parent: Integer).returns(ShellProcessIds) }
    def self.new(shell, parent); end
  end
end
