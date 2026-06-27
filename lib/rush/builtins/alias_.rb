# frozen_string_literal: true

module Rush
  module Builtins
    # `alias [name[=value]...]` defines or prints aliases. With no operands it
    # lists every alias as a single-quoted `name=value` on stdout. An operand
    # containing `=` past its first character defines (the name is everything
    # before that `=`); a bare name prints that alias, or reports `alias: NAME not
    # found` on stderr and yields status 1 while still processing the rest.
    class Alias < Base
      ASSIGN = /\A(.+?)=(.*)\z/m

      def call
        return list if operands.empty?

        operands.reduce(success) { |status, operand| keep(status, handle(operand)) }
      end

      private

      def handle(operand)
        match = ASSIGN.match(operand)
        match ? define(match[1], match[2]) : query(operand)
      end

      def define(name, value)
        aliases.define(name, value)
        success
      end

      def query(name)
        value = aliases.value(name)
        return show(name, value) if value

        stderr.puts("alias: #{name} not found")
        failure(1)
      end

      def list
        aliases.listing.each { |name, value| show(name, value) }
        success
      end

      def show(name, value)
        stdout.puts(single_quote("#{name}=#{value}"))
        success
      end

      def single_quote(text) = "'#{text.gsub("'", %q('"'"'))}'"

      def keep(status, result) = status.success? ? result : status

      def aliases = executor.state.aliases
    end
  end
end
