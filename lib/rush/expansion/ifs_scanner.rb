# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # The POSIX §2.6.5 field-splitting state machine. It runs once, left to right,
    # over the expanded parts ([text, splittable, break]) so a delimiter that
    # spans two adjacent unquoted expansions still yields the right (possibly
    # empty) fields. IFS whitespace coalesces and is stripped at the ends; each
    # non-whitespace IFS character delimits a field (so adjacent ones generate
    # empty fields), while a single trailing delimiter is absorbed. Quoted text
    # and a break-flagged part (the elements of $@/$*) anchor or force a field
    # regardless of IFS. A trailing empty, non-anchored field is dropped.
    #
    # The field being built is held in @current (always present, by construction),
    # with completed fields in @done — so the "there is always a current field"
    # invariant is structural, not a runtime fact the reader/checker must infer.
    class IfsScanner
      def initialize(whitespace, others)
        @ws = whitespace
        @others = others
        @done = []
        @current = field
        @pending = false
        @skip = true
      end

      def run(parts)
        parts.each { |part| consume(part) }
        result
      end

      private

      def field
        { text: +'', real: false }
      end

      def consume(part)
        text, splittable, brk = part
        open_field if brk
        splittable ? text.each_char { |char| step(char) } : literal(text)
      end

      def step(char)
        return pend if @ws.include?(char)
        return open_field if @others.include?(char)

        ordinary(char)
      end

      def pend
        (@pending = true unless @skip)
      end

      def ordinary(char)
        flush
        @current[:text] << char
        @skip = false
      end

      def literal(text)
        flush
        @current[:text] << text
        @current[:real] = true
        @skip = false
      end

      def flush
        (open_field if @pending)
      end

      def open_field
        @pending = false
        @done << @current
        @current = field
        @skip = true
      end

      def result
        fields = drop_last? ? @done : @done + [@current]
        fields.map { |entry| entry[:text] }
      end

      def drop_last?
        @current[:text].empty? && !@current[:real]
      end
    end
  end
end
