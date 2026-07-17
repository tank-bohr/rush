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

  class GetoptsParser
    # One getopts parser step's variable updates and status.
    class Result < Data
      extend T::Sig

      sig { returns(String) }
      attr_reader :name

      sig { returns(T.nilable(String)) }
      attr_reader :optarg

      sig { returns(Integer) }
      attr_reader :optind

      sig { returns(T.nilable(String)) }
      attr_reader :message

      sig { returns(Integer) }
      attr_reader :exitstatus

      sig { returns(T::Boolean) }
      attr_reader :keep_optarg

      sig do
        params(name: String, optarg: T.nilable(String), optind: Integer, message: T.nilable(String),
               exitstatus: Integer, keep_optarg: T::Boolean).returns(Result)
      end
      # rubocop:disable Metrics/ParameterLists -- mirrors the keyword Data constructor
      def self.new(name:, optarg:, optind:, message:, exitstatus:, keep_optarg:); end
      # rubocop:enable Metrics/ParameterLists
    end

    # Option character paired with its source argument.
    class Option < Data
      extend T::Sig

      sig { returns(String) }
      attr_reader :argument

      sig { returns(String) }
      attr_reader :name

      sig { params(argument: String, name: String).returns(Option) }
      def self.new(argument:, name:); end
    end
  end
end
