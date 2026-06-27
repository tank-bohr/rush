# frozen_string_literal: true

module Rush
  module Builtins
    # The builtins available in Slice 1. Later slices extend this table.
    DEFAULTS = {
      ':' => Colon, 'true' => True, 'false' => False,
      'echo' => Echo, 'exit' => Exit, 'pwd' => Pwd, 'cd' => Cd
    }.freeze

    def self.default_registry
      Registry.new.tap { |registry| DEFAULTS.each { |name, klass| registry.register(name, klass) } }
    end
  end
end
