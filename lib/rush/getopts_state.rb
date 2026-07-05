# typed: true
# frozen_string_literal: true

module Rush
  # Cursor state for POSIX getopts. OPTIND is public and 1-based, but while
  # parsing an option cluster such as -ab dash already publishes OPTIND=2 after
  # returning -a; the private cursor still points at b in argv[0]. This object
  # keeps that hidden intra-argument cursor and resets it when OPTIND or the
  # argument vector changes.
  class GetoptsState
    extend T::Sig

    sig { returns(Integer) }
    attr_reader :current_index, :cursor, :optind

    sig { void }
    def initialize
      @signature = nil
      @current_index = 0
      @cursor = 1
      @optind = 1
    end

    sig { params(arguments: T::Array[String], optind: Integer).void }
    def prepare(arguments, optind)
      signature = arguments.join("\0")
      reset(signature, optind) if signature != @signature || optind != @optind
    end

    sig { params(arguments: T::Array[String]).returns(T.nilable(String)) }
    def current(arguments)
      arguments[@current_index]
    end

    sig { params(argument: String).returns(String) }
    def option(argument)
      T.must(argument[@cursor])
    end

    sig { params(argument: String).void }
    def consume_option(argument)
      cluster_remains?(argument) ? consume_cluster : consume_final_option
    end

    sig { params(argument: String).returns(T::Boolean) }
    def cluster_remains?(argument)
      @cursor < argument.length - 1
    end

    sig { void }
    def consume_cluster
      @cursor += 1
      @optind = @current_index + 2
    end

    sig { void }
    def consume_final_option
      @current_index += 1
      @cursor = 1
      publish
    end

    sig { void }
    def consume_attached_argument
      @current_index += 1
      @cursor = 1
      publish
    end

    sig { void }
    def consume_detached_argument
      @current_index += 2
      @cursor = 1
      publish
    end

    sig { void }
    def finish
      @cursor = 1
      publish
    end

    sig { void }
    def finish_double_dash
      @current_index += 1
      finish
    end

    private

    sig { params(signature: String, optind: Integer).void }
    def reset(signature, optind)
      @signature = signature
      @current_index = [optind - 1, 0].max
      @cursor = 1
      publish
    end

    sig { void }
    def publish
      @optind = @current_index + 1
    end
  end
end
