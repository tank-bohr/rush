# typed: true
# frozen_string_literal: true

require 'io/wait'

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

      # Adds caught-signal polling only to real IO; StringIO-backed reads stay
      # direct and deterministic.
      class LineReader
        extend T::Sig

        POLL_INTERVAL = 0.01

        sig { params(stream: T.untyped, pending: T.proc.returns(T::Boolean)).void }
        def initialize(stream, pending)
          @stream = stream
          @pending = pending
        end

        sig { returns(T.nilable(String)) }
        def gets
          stream = @stream
          return stream.gets unless stream.is_a?(IO)

          wait_for_line(stream)
        end

        private

        sig { params(stream: IO).returns(T.nilable(String)) }
        def wait_for_line(stream)
          line = +''
          catch(:physical_line) { loop { read_step(stream, line) } }
        end

        sig { params(stream: IO, line: String).void }
        def read_step(stream, line)
          throw(:interrupted, line) if @pending.call
          char = next_char(stream)
          throw(:physical_line, line.empty? ? nil : line) unless char
          append_char(line, char) if char.is_a?(String)
        end

        sig { params(line: String, char: String).void }
        def append_char(line, char)
          line << char
          throw(:physical_line, line) if char == "\n"
        end

        sig { params(stream: IO).returns(T.untyped) }
        def next_char(stream)
          return :wait_readable unless stream.wait_readable(POLL_INTERVAL)

          read_char(stream)
        end

        sig { params(stream: IO).returns(T.untyped) }
        def read_char(stream)
          stream.read_nonblock(1)
        rescue IO::WaitReadable
          :wait_readable
        rescue EOFError
          nil
        end
      end

      # A line whose backslash-pairs all match, leaving one lone trailing
      # backslash: a line-continuation request.
      CONTINUED = /\A(?:[^\\]|\\.)*\\\z/m

      # One output character: an optional escaping backslash and the character.
      PAIR = /(\\)?(.)/m

      sig { params(stdin: T.untyped, raw: T::Boolean, pending: T.proc.returns(T::Boolean)).void }
      def initialize(stdin, raw, pending: -> { false })
        @reader = LineReader.new(stdin, pending)
        @raw = raw
        @chars = T.let([], T::Array[Expansion::ReadChar])
        @complete = T.let(false, T::Boolean)
      end

      sig { returns(T.nilable([T::Array[Expansion::ReadChar], T::Boolean])) }
      def call
        partial = catch(:interrupted) do
          gather
          return [@chars, @complete]
        end
        partial_result(partial)
      end

      private

      sig { params(partial: String).returns(T.nilable([T::Array[Expansion::ReadChar], T::Boolean])) }
      def partial_result(partial)
        decode(partial)
        [@chars, false] unless @chars.empty?
      end

      sig { void }
      def gather
        line = @reader.gets
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
