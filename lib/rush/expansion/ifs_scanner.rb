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

      # One output field under construction. Alongside its literal text it lazily
      # records a distinct pathname pattern only when quoted metacharacters need
      # shielding; a data backslash stays in both forms and is never stripped as
      # if it were synthetic quote provenance.
      class Field
        extend T::Sig

        QUOTED_PATTERN = /[\\*?\[\]\-!^]/
        PATTERNS = { true => QUOTED_PATTERN, false => nil }.freeze

        sig { returns(String) }
        attr_reader :text

        sig { void }
        def initialize
          @text = +''
          @pattern = T.let(nil, T.nilable(String))
          @real = false
        end

        sig { params(text: String, quoted: T::Boolean).void }
        def append(text, quoted)
          fragment = pattern_fragment(text, quoted)
          @pattern = @text.dup if !@pattern && !fragment.equal?(text)
          @pattern&.concat(fragment)
          @text << text
        end

        sig { returns(String) }
        def pattern
          @pattern || @text
        end

        sig { void }
        def mark_real
          @real = true
        end

        sig { returns(T::Boolean) }
        def empty_unreal?
          @text.empty? && !@real
        end

        private

        sig { params(text: String, quoted: T::Boolean).returns(String) }
        def pattern_fragment(text, quoted)
          pattern = PATTERNS.fetch(quoted)
          return text unless pattern && text.match?(pattern)

          text.gsub(pattern) { |meta| "\\#{meta}" }
        end
      end

      sig { params(ifs: Ifs).void }
      def initialize(ifs)
        @ws = ifs.whitespace
        @others = ifs.others
        @preserve_empty_splat = ifs.preserve_empty_splat?
        @done = T.let([], T::Array[Field])
        @current = Field.new
        @pending = false
        @skip = true
      end

      sig { params(parts: T::Array[FieldPart]).returns(T::Array[Field]) }
      def run(parts)
        parts.each { |part| consume(part) }
        result
      end

      private

      sig { params(part: FieldPart).void }
      def consume(part)
        text, splittable, brk, quoted = part
        break_field if brk
        splittable ? text.each_char { |char| step(char) } : literal(text, quoted)
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
        @current.append(char, false)
        @skip = false
      end

      sig { params(text: String, quoted: T::Boolean).void }
      def literal(text, quoted)
        flush
        @current.append(text, quoted)
        @current.mark_real
        @skip = false
      end

      sig { void }
      def flush
        (open_field if @pending)
      end

      # An unquoted null $@/$* element disappears when the first IFS character
      # is whitespace; otherwise its forced boundary remains an empty field.
      sig { void }
      def break_field
        return reset_field if !@preserve_empty_splat && @current.empty_unreal?

        open_field
      end

      sig { void }
      def open_field
        @done << @current
        reset_field
      end

      sig { void }
      def reset_field
        @pending = false
        @current = Field.new
        @skip = true
      end

      sig { returns(T::Array[Field]) }
      def result
        @done << @current unless drop_last?
        @done
      end

      sig { returns(T::Boolean) }
      def drop_last?
        @current.empty_unreal?
      end
    end
  end
end
