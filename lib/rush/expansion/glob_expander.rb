# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Pathname expansion (step 3): a field is replaced by the sorted pathnames it
    # matches; a field that matches nothing — or any field while `set -f`
    # (noglob) is in effect — stays literal. IfsScanner::Field carries literal
    # text separately from its lazily shielded pattern, so a data backslash is
    # preserved when no pathname replaces the field.
    class GlobExpander
      extend T::Sig

      PATHNAME_PATTERN = /(?<!\\)(?:\\\\)*(?:[*?]|\[(?:\\.|[^\\\]])*\])/

      sig { params(executor: Executor).void }
      def initialize(executor)
        @executor = executor
      end

      sig { params(field: IfsScanner::Field, expanded: T::Array[String]).void }
      def append(field, expanded)
        pattern = field.pattern
        return expanded << field.text unless expandable?(pattern)

        append_matches(field, expanded, matches(pattern))
      end

      private

      sig { params(pattern: String).returns(T::Boolean) }
      def expandable?(pattern)
        !@executor.state.options.on?(:noglob) && pattern.match?(PATHNAME_PATTERN)
      end

      sig { params(pattern: String).returns(T::Array[String]) }
      def matches(pattern)
        locale = @executor.state.variables.locale_settings
        @executor.system.glob(pattern, locale: locale)
      end

      sig { params(field: IfsScanner::Field, expanded: T::Array[String], matches: T::Array[String]).void }
      def append_matches(field, expanded, matches)
        matches.empty? ? expanded << field.text : expanded.concat(matches)
      end
    end
  end
end
