# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Pathname expansion (step 3): a field is replaced by the sorted pathnames it
    # matches; a field that matches nothing — or any field while `set -f`
    # (noglob) is in effect — stays literal. Quoted metacharacters were
    # backslash-escaped upstream so they match literally; the backslashes are
    # removed here whenever no expansion takes their place.
    class GlobExpander
      def initialize(executor)
        @executor = executor
      end

      def expand(field)
        return [unescape(field)] if @executor.state.options.on?(:noglob)

        matches = @executor.system.glob(field)
        matches.empty? ? [unescape(field)] : matches
      end

      private

      def unescape(field)
        field.gsub(/\\(.)/, '\1')
      end
    end
  end
end
