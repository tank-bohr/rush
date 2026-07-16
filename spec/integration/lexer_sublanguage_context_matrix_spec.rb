# frozen_string_literal: true

RSpec.describe 'lexer sublanguage context matrix' do
  def parse_state(source, interactive:)
    lexer = Rush::Lexer.new(source, interactive: interactive)
    Rush::Parser.new(lexer).parse
    :complete
  rescue Rush::IncompleteInput
    :incomplete
  rescue Rush::ParseError
    :syntax_error
  end

  matrix = {
    'fully nested substitutions' => {
      source: "printf \"%s\" \"${x:-$(printf %s \"$((1 + 2))\")}\"\n",
      interactive: :complete,
      final: :complete
    },
    'single quote' => {
      source: "printf '%s' 'word\n",
      interactive: :incomplete,
      final: :incomplete
    },
    'double quote' => {
      source: "printf \"%s\" \"word\n",
      interactive: :incomplete,
      final: :incomplete
    },
    'braced parameter' => {
      source: "printf \"%s\" \"${x:-word\n",
      interactive: :incomplete,
      final: :incomplete
    },
    'command substitution' => {
      source: "printf \"%s\" \"$(printf x\n",
      interactive: :incomplete,
      final: :incomplete
    },
    'arithmetic expansion' => {
      source: "printf \"%s\" \"$((1 + 2\n",
      interactive: :incomplete,
      final: :incomplete
    },
    'case construct' => {
      source: "case x in\nx) printf yes;;\n",
      interactive: :incomplete,
      final: :incomplete
    },
    'unexpected closing token' => {
      source: "printf x )\n",
      interactive: :syntax_error,
      final: :syntax_error
    },
    'trailing line continuation' => {
      source: ['printf x \\', "\n"].join,
      interactive: :incomplete,
      final: :complete
    },
    'unterminated here-document' => {
      source: "cat <<EOF\nbody\n",
      interactive: :incomplete,
      final: :complete
    }
  }.freeze

  matrix.each do |label, row|
    it "characterizes #{label} at the interactive/final boundary" do
      states = [
        parse_state(row.fetch(:source), interactive: true),
        parse_state(row.fetch(:source), interactive: false)
      ]

      expect(states).to eq([row.fetch(:interactive), row.fetch(:final)])
    end
  end
end
