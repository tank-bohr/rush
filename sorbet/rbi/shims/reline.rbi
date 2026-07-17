# typed: true
# frozen_string_literal: true

# Sorbet's stdlib Reline declaration mirrors its variadic forwarding API but
# leaves the result untyped. Rush uses the ordinary prompt/history form, whose
# only non-String result is nil at EOF.
module Reline
  sig do
    params(args: T.untyped, kwargs: T.untyped, block: T.untyped).returns(T.nilable(String))
  end
  def self.readline(*args, **kwargs, &block); end
end
