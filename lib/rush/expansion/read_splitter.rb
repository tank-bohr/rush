# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Field splitting for the `read` builtin over an escape-annotated line:
    # ReadFieldScanner splits on unescaped IFS delimiters into at most `count`
    # fields (the last keeps the remainder verbatim, trailing IFS whitespace
    # removed), and the result is padded with empty strings up to `count`.
    # A null IFS does not split — the whole line is one field, untrimmed.
    class ReadSplitter
      extend T::Sig

      sig { params(ifs: T.nilable(String), count: Integer).void }
      def initialize(ifs, count)
        @ifs = Ifs.new(ifs)
        @count = count
      end

      sig { params(chars: T::Array[ReadChar]).returns(T::Array[String]) }
      def split(chars)
        return pad([text(chars)]) if @ifs.null?

        pad(ReadFieldScanner.new(@ifs, @count).run(chars))
      end

      private

      sig { params(chars: T::Array[ReadChar]).returns(String) }
      def text(chars)
        chars.map(&:first).join
      end

      sig { params(fields: T::Array[String]).returns(T::Array[String]) }
      def pad(fields)
        (fields.each + [''].cycle).take(@count)
      end
    end
  end
end
