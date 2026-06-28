# frozen_string_literal: true

# Maps a word segment to a readable kind symbol for assertions. The production
# code dropped the `kind` field in favour of segment subtypes; this keeps the
# lexer specs readable without resurrecting it.
module SegmentHelpers
  KINDS = {
    Rush::AST::LiteralSegment => :literal,
    Rush::AST::ParamSegment => :param,
    Rush::AST::CommandSegment => :command,
    Rush::AST::ArithSegment => :arith
  }.freeze

  def segment_kind(segment) = KINDS.fetch(segment.class)
end
