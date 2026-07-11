# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # The count-limited, escape-aware field scanner behind ReadSplitter — a
    # transcription of dash's ifsbreakup(maxargs): fields split off until the
    # variable budget is spent; the delimiter that spends it starts the
    # remainder, which accumulates verbatim with a cut mark (dash's `r`)
    # tracking removable trailing IFS whitespace. Escaped characters are plain
    # content: never delimiters, they end a whitespace run (dash's region
    # boundary) and never touch the cut mark — reproducing dash's remainder
    # edge cases exactly (see the unit spec).
    class ReadFieldScanner
      extend T::Sig

      # The collected fields plus the field being built, carrying dash's `r`
      # mark: the position from which the final field's trailing text is cut.
      class Fields
        extend T::Sig

        sig { void }
        def initialize
          @done = T.let([], T::Array[String])
          @text = T.let(+'', String)
          @cut = T.let(nil, T.nilable(Integer))
        end

        sig { params(char: String).void }
        def append(char)
          @text << char
        end

        sig { returns(T::Boolean) }
        def empty?
          @text.empty?
        end

        sig { void }
        def close
          @done << @text
          @text = +''
        end

        # Records the cut position — the start of removable trailing text
        # (dash's `r`) — keeping the earliest one until uncut clears it.
        sig { void }
        def cut
          @cut ||= @text.length
        end

        sig { void }
        def uncut
          @cut = nil
        end

        sig { returns(T::Array[String]) }
        def result
          cut = @cut
          tail = cut ? T.must(@text[0, cut]) : @text
          tail.empty? ? @done : @done + [tail]
        end
      end

      sig { params(ifs: Ifs, count: Integer).void }
      def initialize(ifs, count)
        @ifs = ifs
        @left = count
        @fields = T.let(Fields.new, Fields)
        @spaced = T.let(false, T::Boolean) # dash's ifsspc: in a whitespace-delimiter run
      end

      sig { params(chars: T::Array[ReadChar]).returns(T::Array[String]) }
      def run(chars)
        chars.each { |char, escaped| escaped ? shielded(char) : consume(char) }
        @fields.result
      end

      private

      sig { params(char: String).void }
      def consume(char)
        return tail(char) if @left.zero?
        return absorb(char) if @spaced && ifs?(char)

        head(char)
      end

      # A backslash-escaped character: plain content, never a delimiter. It
      # ends any whitespace run (in dash a region boundary resets ifsspc) and
      # leaves the cut mark alone (dash never scans the gap it sits in). The
      # zero-width joint a line continuation leaves (['', true]) rides the same
      # path: it only breaks the run.
      sig { params(char: String).void }
      def shielded(char)
        @spaced = false
        @fields.append(char)
      end

      # Inside a whitespace-delimiter run an IFS char joins the delimiter:
      # more whitespace keeps the run open, one non-whitespace IFS character
      # closes it.
      sig { params(char: String).void }
      def absorb(char)
        @spaced = @ifs.whitespace?(char)
      end

      sig { params(char: String).void }
      def head(char)
        return delimiter(char) if ifs?(char)

        @spaced = false
        @fields.append(char)
      end

      # An unescaped IFS delimiter: whitespace before any field content is
      # skipped; a delimiter splits a field while variables remain, and the
      # one that spends the last variable opens the remainder.
      sig { params(char: String).void }
      def delimiter(char)
        @spaced = @ifs.whitespace?(char)
        return skip_leading if @spaced && @fields.empty?

        (@left -= 1).zero? ? removable(char) : @fields.close
      end

      sig { void }
      def skip_leading
        @spaced = false
      end

      # Removable trailing text: the delimiter that spends the last variable
      # (the remainder accumulates verbatim from it) and, later, IFS whitespace
      # extending the trailing run — cut off unless real content follows.
      sig { params(char: String).void }
      def removable(char)
        @fields.cut
        @fields.append(char)
      end

      # Remainder mode (dash's exhausted maxargs): IFS whitespace extends the
      # removable trailing run; anything else is content and clears the cut —
      # except a single non-whitespace IFS char directly closing a run.
      sig { params(char: String).void }
      def tail(char)
        return removable(char) if @ifs.whitespace?(char)

        @fields.uncut unless @ifs.other?(char) && @spaced
        @spaced = false
        @fields.append(char)
      end

      sig { params(char: String).returns(T::Boolean) }
      def ifs?(char)
        @ifs.whitespace?(char) || @ifs.other?(char)
      end
    end
  end
end
