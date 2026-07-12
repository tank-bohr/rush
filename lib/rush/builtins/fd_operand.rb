# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # Resolves test/[ operands that name shell file descriptors through the
    # command's logical IoTable. In production, a redirected File/pipe/tty has a
    # real fileno; rewriting to that descriptor lets the kernel's existing
    # File/IO predicates answer exactly as if the shell had applied dup2.
    class FdOperand
      extend T::Sig

      PATH_OPERATORS = %w[-e -f -d -r -w -x -s -p -b -c -S -g -u].freeze
      STANDARD_PATHS = { '/dev/stdin' => 0, '/dev/stdout' => 1, '/dev/stderr' => 2 }.freeze
      FD_PATH = %r{\A/(?:dev|proc/self)/fd/(\d+)\z}
      CLOSED_PATH = '/dev/fd/-'
      CLOSED_DESCRIPTOR = '-1'

      sig { params(io: IoTable).void }
      def initialize(io)
        @io = io
      end

      sig { params(operator: String, operand: String).returns(String) }
      def resolve(operator, operand)
        return descriptor(operand) if operator == '-t'
        return operand unless PATH_OPERATORS.include?(operator)

        path(operand)
      end

      private

      # Steep 2 crashes internally on &:to_s here, so keep the explicit block.
      # rubocop:disable Style/SymbolProc
      sig { params(operand: String).returns(String) }
      def descriptor(operand)
        fd = integer(operand)
        fd ? rewrite(fd, operand, CLOSED_DESCRIPTOR) { |fileno| fileno.to_s } : operand
      end
      # rubocop:enable Style/SymbolProc

      sig { params(operand: String).returns(String) }
      def path(operand)
        fd = path_fd(operand)
        fd ? rewrite(fd, operand, CLOSED_PATH) { |fileno| "/dev/fd/#{fileno}" } : operand
      end

      sig do
        params(fd: Integer, original: String, closed: String,
               blk: T.proc.params(fileno: Integer).returns(String)).returns(String)
      end
      def rewrite(fd, original, closed, &blk)
        entry = @io.entry(fd)
        return original unless entry
        return closed if entry.closed?

        replacement(entry, original, &blk)
      end

      sig do
        params(entry: FdEntry, original: String,
               blk: T.proc.params(fileno: Integer).returns(String)).returns(String)
      end
      def replacement(entry, original, &blk)
        fileno = entry.stream.fileno
        fileno ? yield(fileno) : original
      rescue IOError, SystemCallError
        original
      end

      sig { params(operand: String).returns(T.nilable(Integer)) }
      def path_fd(operand)
        standard = STANDARD_PATHS.fetch(operand, nil)
        return standard if standard

        match = FD_PATH.match(operand)
        integer(match[1].to_s) if match
      end

      sig { params(text: String).returns(T.nilable(Integer)) }
      def integer(text)
        Integer(text, 10) if text.match?(/\A\s*\+?\d+\s*\z/)
      end
    end
  end
end
