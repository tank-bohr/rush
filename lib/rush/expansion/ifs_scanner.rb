# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # The POSIX §2.6.5 field-splitting state machine. It runs once, left to right,
    # over the expanded parts ([text, splittable, break, quoted]) so a delimiter that
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
      extend T::Sig

      # One output field under construction: its text and whether quoted input or
      # $@/$* anchoring made it real even when the text is empty.
      class Field
        extend T::Sig

        sig { returns(String) }
        attr_reader :text

        sig { void }
        def initialize
          @text = +''
          @real = false
        end

        sig { params(text: String).void }
        def append(text)
          @text << text
        end

        sig { void }
        def mark_real
          @real = true
        end

        sig { returns(T::Boolean) }
        def empty_unreal?
          @text.empty? && !@real
        end
      end

      sig { params(whitespace: T::Array[String], others: T::Array[String]).void }
      def initialize(whitespace, others)
        @ws = whitespace
        @others = others
        @done = T.let([], T::Array[Field])
        @current = Field.new
        @pending = false
        @skip = true
      end

      sig { params(parts: T::Array[FieldPart]).returns(T::Array[String]) }
      def run(parts)
        parts.each { |part| consume(part) }
        result
      end

      private

      sig { params(part: FieldPart).void }
      def consume(part)
        text, splittable, brk, = part
        open_field if brk
        splittable ? text.each_char { |char| step(char) } : literal(text)
      end

      sig { params(char: String).void }
      def step(char)
        return pend if @ws.include?(char)
        return open_field if @others.include?(char)

        ordinary(char)
      end

      sig { void }
      def pend
        (@pending = true unless @skip)
      end

      sig { params(char: String).void }
      def ordinary(char)
        flush
        @current.append(char)
        @skip = false
      end

      sig { params(text: String).void }
      def literal(text)
        flush
        @current.append(text)
        @current.mark_real
        @skip = false
      end

      sig { void }
      def flush
        (open_field if @pending)
      end

      sig { void }
      def open_field
        @pending = false
        @done << @current
        @current = Field.new
        @skip = true
      end

      sig { returns(T::Array[String]) }
      def result
        fields = drop_last? ? @done : @done + [@current]
        fields.map(&:text)
      end

      sig { returns(T::Boolean) }
      def drop_last?
        @current.empty_unreal?
      end
    end
  end
end
