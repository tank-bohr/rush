# typed: true
# frozen_string_literal: true

module Rush
  # A `-abc` / `+abc` cluster of single-letter options, the shape POSIX shares
  # between the set builtin and the sh invocation line (XCU set / sh): the
  # leading sign and the letters after it. parse answers nil for anything
  # else — `--`, a lone dash or plus, or a plain operand.
  class OptionCluster
    extend T::Sig

    sig { returns(String) }
    attr_reader :sign

    sig { returns(T::Array[String]) }
    attr_reader :letters

    sig { params(arg: T.nilable(String)).returns(T.nilable(OptionCluster)) }
    def self.parse(arg)
      return unless arg.is_a?(String) && arg.length > 1 && arg != '--' && arg.start_with?('-', '+')

      new(arg)
    end

    sig { params(flag: String).void }
    def initialize(flag)
      sign, *letters = flag.chars
      @sign = T.must(sign)
      @letters = T.let(letters, T::Array[String])
    end

    # Yield each option letter with the cluster's sign, the shape both
    # consumers toggle by.
    sig { params(blk: T.proc.params(letter: String, sign: String).void).void }
    def each_letter(&blk)
      letters.each { |letter| yield(letter, sign) }
    end
  end
end
