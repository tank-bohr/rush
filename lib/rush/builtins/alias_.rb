# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `alias [name[=value]...]` defines or prints aliases. With no operands it
    # lists every alias as a single-quoted `name=value` on stdout. An operand
    # containing `=` past its first character defines (the name is everything
    # before that `=`); a bare name prints that alias, or reports `alias: NAME not
    # found` on stderr and yields status 1 while still processing the rest.
    class Alias < Base
      extend T::Sig

      ASSIGN = /\A(.+?)=(.*)\z/m

      sig { returns(T.untyped) }
      def call
        return list if operands.empty?

        operands.reduce(success) { |status, operand| keep(status, handle(operand)) }
      end

      private

      sig { params(operand: T.untyped).returns(T.untyped) }
      def handle(operand)
        match = ASSIGN.match(operand)
        match ? define(match[1], match[2]) : query(operand)
      end

      sig { params(name: T.untyped, value: T.untyped).returns(T.untyped) }
      def define(name, value)
        aliases.define(name, value)
        success
      end

      sig { params(name: T.untyped).returns(T.untyped) }
      def query(name)
        value = aliases.value(name)
        return show(name, value) if value

        stderr.puts("alias: #{name} not found")
        failure(1)
      end

      sig { returns(T.untyped) }
      def list
        aliases.listing.each { |name, value| show(name, value) }
        success
      end

      sig { params(name: T.untyped, value: T.untyped).returns(T.untyped) }
      def show(name, value)
        stdout.puts(single_quote("#{name}=#{value}"))
        success
      end

      sig { params(text: T.untyped).returns(String) }
      def single_quote(text)
        "'#{text.gsub("'", %q('"'"'))}'"
      end

      sig { params(status: T.untyped, result: T.untyped).returns(T.untyped) }
      def keep(status, result)
        status.success? ? result : status
      end

      sig { returns(T.untyped) }
      def aliases
        executor.state.aliases
      end
    end
  end
end
