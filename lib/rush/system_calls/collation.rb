# typed: true
# frozen_string_literal: true

require 'fiddle'
require_relative 'regex_abi'

module Rush
  class SystemCalls
    # Optional glibc bridge for the locale data Ruby does not expose. POSIX ERE
    # matching supplies bracket classes/equivalence/collating elements/ranges;
    # strcoll supplies pathname order. regex_t is opaque at the Fiddle boundary,
    # so RegexAbi admits only glibc-2 Linux with 32/64-bit words before this class
    # loads native calls; the Docker C probe pins its exact size and alignment.
    # Unknown ABIs, including a future glibc 3, fall back before regcomp runs.
    # One cohesive native-resource boundary; splitting function loading from
    # regex ownership would separate lifecycle halves only to satisfy a metric.
    # rubocop:disable Metrics/ClassLength
    class Collation
      extend T::Sig

      LC_CTYPE = 0
      LC_COLLATE = 3
      REG_EXTENDED = 1
      REGEX_BYTES = RegexAbi::REGEX_BYTES
      MUTEX = Thread::Mutex.new
      SIGNATURES = {
        setlocale: [[Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP],
        regcomp: [[Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT],
        regexec: [[Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T,
                   Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_INT],
        regfree: [[Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID],
        strcoll: [[Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT]
      }.freeze

      sig { void }
      def initialize
        @functions = T.let(load_functions, T::Hash[Symbol, T.untyped])
      end

      sig { returns(T::Boolean) }
      def available?
        @functions.any?
      end

      sig do
        params(pattern: String, text: String, settings: T::Array[String],
               fallback: T.proc.returns(T::Boolean)).returns(T::Boolean)
      end
      def match_shell?(pattern, text, settings, &fallback)
        return yield unless available?

        match?(PosixPattern.new(pattern).source, text, settings)
      end

      sig do
        params(pattern: String, settings: T::Array[String],
               fallback: T.proc.returns(T::Array[String])).returns(T::Array[String])
      end
      def glob(pattern, settings, &fallback)
        return yield unless available?

        regex = PosixPattern.new(pattern).source
        matches = candidates(pattern).select { |path| match?(regex, path, settings) }
        matches.sort { |left, right| compare(left, right, settings) }
      end

      sig { returns(T::Array[String]) }
      def default_settings
        %w[LC_COLLATE LC_CTYPE].map { |category| locale_value(category) }
      end

      sig { params(regex: String, text: String, settings: T::Array[String]).returns(T::Boolean) }
      def match?(regex, text, settings)
        MUTEX.synchronize do
          activate(settings)
          compiled(regex) { |pointer| call(:regexec, pointer, text, 0, nil, 0).zero? }
        end
      end

      sig { params(left: String, right: String, settings: T::Array[String]).returns(Integer) }
      def compare(left, right, settings)
        MUTEX.synchronize do
          activate(settings)
          verdict = call(:strcoll, left, right)
          verdict.zero? ? T.must(left.b <=> right.b) : verdict
        end
      end

      private

      sig { params(pattern: String).returns(T::Array[String]) }
      def candidates(pattern)
        source = PosixPattern.new(pattern).glob_source
        Dir.glob(source, sort: false)
      end

      sig { params(category: String).returns(String) }
      def locale_value(category)
        values = [ENV.fetch('LC_ALL', nil), ENV.fetch(category, nil), ENV.fetch('LANG', nil)].compact
        values.find { |value| !value.empty? } || 'C'
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def load_functions
        handle = Fiddle::Handle::DEFAULT
        return {} unless RegexAbi.available?(handle)

        SIGNATURES.to_h { |name, signature| [name, native_function(handle, name, signature)] }
      rescue Fiddle::DLError
        {}
      end

      sig { params(handle: T.untyped, name: Symbol, signature: T.untyped).returns(T.untyped) }
      def native_function(handle, name, signature)
        arguments, result = signature
        Fiddle::Function.new(handle[name.to_s], arguments, result)
      end

      sig { params(name: Symbol, args: T.untyped).returns(T.untyped) }
      def call(name, *args)
        @functions.fetch(name).call(*args)
      end

      sig { params(regex: String, blk: T.proc.params(pointer: T.untyped).returns(T::Boolean)).returns(T::Boolean) }
      def compiled(regex, &blk)
        pointer = Fiddle::Pointer.malloc(REGEX_BYTES, Fiddle::RUBY_FREE)
        return false if call(:regcomp, pointer, regex, REG_EXTENDED).nonzero?

        free_after(pointer, &blk)
      end

      sig do
        params(pointer: T.untyped,
               blk: T.proc.params(pointer: T.untyped).returns(T::Boolean)).returns(T::Boolean)
      end
      def free_after(pointer, &blk)
        yield(pointer)
      ensure
        call(:regfree, pointer)
      end

      sig { params(settings: T::Array[String]).void }
      def activate(settings)
        install(LC_COLLATE, settings.fetch(0))
        install(LC_CTYPE, settings.fetch(1))
      end

      # setlocale refusing the requested name (NULL) falls back to the C
      # locale; the effect lives in libc state, so there is nothing to return.
      sig { params(category: Integer, requested: String).void }
      def install(category, requested)
        result = call(:setlocale, category, requested)
        return unless result.null?

        call(:setlocale, category, 'C')
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
