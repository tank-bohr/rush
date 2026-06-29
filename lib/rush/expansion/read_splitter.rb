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
      def initialize(ifs, count)
        @ifs = Ifs.new(ifs)
        @count = count
      end

      def split(line)
        return pad([line]) if @ifs.null?

        pad(trim_last(line.sub(leading, '').split(delimiter, @count)))
      end

      private

      # A field delimiter: one non-whitespace IFS char with any adjacent IFS
      # whitespace, or a run of IFS whitespace on its own.
      def delimiter
        Regexp.new("#{ws}*(?:#{Regexp.union(@ifs.others).source})#{ws}*|#{ws}+")
      end

      def leading
        /\A#{ws}+/
      end

      def trim_last(fields)
        *rest, last = fields
        last ? rest + [last.sub(/#{ws}+\z/, '')] : rest
      end

      def ws
        "(?:#{Regexp.union(@ifs.whitespace).source})"
      end

      def pad(fields)
        (fields.each + [''].cycle).take(@count)
      end
    end
  end
end
