# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # The operator vocabulary of `test`/`[`, shared by the argument-count
    # front end (TestExpr) and the recursive-descent grammar (TestGrammar).
    # The tables map to lambdas, not method symbols, so each primary carries
    # its operand types past both checkers (the #: types each lambda for
    # Steep, the T.let the table for Sorbet). File primaries ask the
    # SystemCalls port; -t parses its operand as a file-descriptor number
    # first, rejecting non-numbers like dash's "Illegal number" (exit 2).
    module TestOperators
      UNARY = T.let({
        '-n' => ->(_files, val) { !val.empty? },                          #: ^(SystemCalls, String) -> bool
        '-z' => ->(_files, val) { val.empty? },                           #: ^(SystemCalls, String) -> bool
        '-t' => ->(files, val) { files.tty_fd?(fd_number(val)) },         #: ^(SystemCalls, String) -> bool
        '-e' => ->(files, val) { files.exist?(val) },                     #: ^(SystemCalls, String) -> bool
        '-f' => ->(files, val) { files.file?(val) },                      #: ^(SystemCalls, String) -> bool
        '-d' => ->(files, val) { files.directory?(val) },                 #: ^(SystemCalls, String) -> bool
        '-r' => ->(files, val) { files.readable?(val) },                  #: ^(SystemCalls, String) -> bool
        '-w' => ->(files, val) { files.writable?(val) },                  #: ^(SystemCalls, String) -> bool
        '-x' => ->(files, val) { files.executable?(val) },                #: ^(SystemCalls, String) -> bool
        '-s' => ->(files, val) { files.file_nonempty?(val) },             #: ^(SystemCalls, String) -> bool
        '-h' => ->(files, val) { files.symlink?(val) },                   #: ^(SystemCalls, String) -> bool
        '-L' => ->(files, val) { files.symlink?(val) },                   #: ^(SystemCalls, String) -> bool
        '-p' => ->(files, val) { files.pipe?(val) },                      #: ^(SystemCalls, String) -> bool
        '-b' => ->(files, val) { files.blockdev?(val) },                  #: ^(SystemCalls, String) -> bool
        '-c' => ->(files, val) { files.chardev?(val) },                   #: ^(SystemCalls, String) -> bool
        '-S' => ->(files, val) { files.socket?(val) },                    #: ^(SystemCalls, String) -> bool
        '-g' => ->(files, val) { files.setgid?(val) },                    #: ^(SystemCalls, String) -> bool
        '-u' => ->(files, val) { files.setuid?(val) }                     #: ^(SystemCalls, String) -> bool
      }.freeze, T::Hash[String, T.proc.params(files: SystemCalls, val: String).returns(T::Boolean)])
      STRING = T.let({
        '=' => ->(lhs, rhs) { lhs == rhs },  #: ^(String, String) -> bool
        '!=' => ->(lhs, rhs) { lhs != rhs }  #: ^(String, String) -> bool
      }.freeze, T::Hash[String, T.proc.params(lhs: String, rhs: String).returns(T::Boolean)])
      INTEGER = T.let({
        '-eq' => ->(lhs, rhs) { lhs == rhs },  #: ^(Integer, Integer) -> bool
        '-ne' => ->(lhs, rhs) { lhs != rhs },  #: ^(Integer, Integer) -> bool
        '-gt' => ->(lhs, rhs) { lhs > rhs },   #: ^(Integer, Integer) -> bool
        '-ge' => ->(lhs, rhs) { lhs >= rhs },  #: ^(Integer, Integer) -> bool
        '-lt' => ->(lhs, rhs) { lhs < rhs },   #: ^(Integer, Integer) -> bool
        '-le' => ->(lhs, rhs) { lhs <= rhs }   #: ^(Integer, Integer) -> bool
      }.freeze, T::Hash[String, T.proc.params(lhs: Integer, rhs: Integer).returns(T::Boolean)])

      # A string that may name an integer for the numeric primaries: #value is its
      # integer when it is a valid (optionally signed, blank-padded) decimal, else
      # nil. Underscores and 0x are rejected, matching dash's strtol-strictness.
      class MaybeInteger
        PATTERN = /\A\s*[+-]?\d+\s*\z/

        def initialize(text)
          @text = text
        end

        def valid?
          @text.match?(PATTERN)
        end

        def value
          Integer(@text, 10) if valid?
        end
      end

      def self.unary?(word)
        UNARY.key?(word)
      end

      def self.binary?(word)
        STRING.key?(word) || INTEGER.key?(word)
      end

      def self.unary(op)
        UNARY.fetch(op)
      end

      def self.apply_binary(op, lhs, rhs)
        string = STRING[op]
        return string.call(lhs, rhs) if string

        INTEGER.fetch(op).call(to_int(lhs), to_int(rhs))
      end

      def self.to_int(text)
        MaybeInteger.new(text).value || raise(TestError, "#{text}: integer expected")
      end

      def self.fd_number(text)
        MaybeInteger.new(text).value || raise(TestError, "Illegal number: #{text}")
      end
    end
  end
end
