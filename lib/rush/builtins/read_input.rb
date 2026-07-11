# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # Reads one logical line for the `read` builtin from the given stream.
    # Without -r a backslash escapes the next character (annotating it as
    # protected from field splitting) and a trailing unescaped backslash joins
    # the next physical line. `call` returns the annotated characters plus
    # whether the line was complete — terminated by a newline before end of
    # file, dash's read exit-status rule.
    class ReadInput
      extend T::Sig

      # A line whose backslash-pairs all match, leaving one lone trailing
      # backslash: a line-continuation request.
      CONTINUED = /\A(?:[^\\]|\\.)*\\\z/m

      # One output character: an optional escaping backslash and the character.
      PAIR = /(\\)?(.)/m

      sig { params(stdin: T.untyped, raw: T::Boolean).void }
      def initialize(stdin, raw)
        @stdin = stdin
        @raw = raw
        @chars = T.let([], T::Array[Expansion::ReadChar])
        @complete = T.let(false, T::Boolean)
      end

      sig { returns([T::Array[Expansion::ReadChar], T::Boolean]) }
      def call
        gather
        [@chars, @complete]
      end

      private

      sig { void }
      def gather
        line = @stdin.gets
        return @complete = false unless line

        @complete = line.end_with?("\n")
        gather if decode(line.delete_suffix("\n"))
      end

      # Appends the line's annotated characters; true means a continuation is
      # pending and the next physical line belongs to this logical one.
      sig { params(text: String).returns(T::Boolean) }
      def decode(text)
        return cook(text) unless @raw

        verbatim(text)
        false
      end

      sig { params(text: String).void }
      def verbatim(text)
        text.each_char { |char| @chars << [char, false] }
      end

      # A continuation leaves a zero-width escaped joint (['', true]) where the
      # lines meet: dash's region boundary, which ends a whitespace-delimiter
      # run in the splitter without contributing a character.
      sig { params(text: String).returns(T::Boolean) }
      def cook(text)
        pending = text.match?(CONTINUED)
        body = pending ? T.must(text[0..-2]) : text
        body.scan(PAIR) { |escape, char| @chars << [T.must(char), escape == '\\'] }
        (@chars << ['', true]) if pending
        pending
      end
    end
  end
end
