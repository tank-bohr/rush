# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Field splitting for the `read` builtin: strip leading IFS whitespace, split
    # into at most `count` fields (the last keeps the unsplit remainder, with
    # trailing IFS whitespace removed) and pad with empty strings up to `count`.
    # Uses the full three IFS cases (via the Ifs delimiter sets): whitespace
    # coalesces, each non-whitespace IFS character delimits (generating empty
    # fields), a null IFS does not split.
    class ReadSplitter
      extend T::Sig

      sig { params(ifs: T.nilable(String), count: Integer).void }
      def initialize(ifs, count)
        @ifs = Ifs.new(ifs)
        @count = count
      end

      sig { params(line: String).returns(T::Array[String]) }
      def split(line)
        return pad([line]) if @ifs.null?

        pad(trim_last(line.sub(leading, '').split(delimiter, @count)))
      end

      private

      # A field delimiter: one non-whitespace IFS char with any adjacent IFS
      # whitespace, or a run of IFS whitespace on its own.
      sig { returns(Regexp) }
      def delimiter
        Regexp.new("#{ws}*(?:#{Regexp.union(@ifs.others).source})#{ws}*|#{ws}+")
      end

      sig { returns(Regexp) }
      def leading
        /\A#{ws}+/
      end

      sig { params(fields: T::Array[String]).returns(T::Array[String]) }
      def trim_last(fields)
        *rest, last = fields
        last ? rest + [last.sub(/#{ws}+\z/, '')] : rest
      end

      sig { returns(String) }
      def ws
        "(?:#{Regexp.union(@ifs.whitespace).source})"
      end

      sig { params(fields: T::Array[String]).returns(T::Array[String]) }
      def pad(fields)
        (fields.each + [''].cycle).take(@count)
      end
    end
  end
end
