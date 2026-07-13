# typed: true
# frozen_string_literal: true

module Rush
  # Coalesces caught signals until the evaluator reaches a safe command
  # boundary. POSIX does not require multiple instances of one signal to queue;
  # dash drains distinct pending signals in signal-number order.
  class PendingSignals
    extend T::Sig

    sig { void }
    def initialize
      @names = T.let(empty, T::Hash[String, T::Boolean])
    end

    # Called from Ruby's Signal.trap block: deliberately only one Hash write,
    # with no parser, evaluator, mutex or user shell code in handler context.
    sig { params(name: String).void }
    def record(name)
      @names[name] = true
    end

    sig { params(blk: T.proc.params(name: String).void).void }
    def drain(&blk)
      take.each(&blk) until @names.empty?
    end

    sig { returns(T.nilable(String)) }
    def first
      @names.keys.min_by { |name| Signals.number(name) }
    end

    sig { returns(T::Boolean) }
    def any?
      @names.any?
    end

    sig { void }
    def clear
      @names.clear
    end

    private

    sig { returns(T::Array[String]) }
    def take
      names = @names
      @names = empty
      names.keys.sort_by { |name| Signals.number(name) }
    end

    sig { returns(T::Hash[String, T::Boolean]) }
    def empty
      {} #: Hash[String, bool]
    end
  end
end
