# frozen_string_literal: true

RSpec.describe Rush::CommandText do
  def render(source)
    entry = Rush::Parser.new(Rush::Lexer.new(source)).parse.entries.fetch(0)
    described_class.render(entry.and_or)
  end

  # Every pair below is dash 0.5.13's own jobs-column text for the same
  # source (probed off-tty under set -m); the differential corpus re-checks
  # the same shapes against the live oracle.
  canon = {
    'sleep 5' => 'sleep 5',
    "sh -c 'kill -TSTP $$' ss" => 'sh -c "kill -TSTP \$\$" ss',
    'sleep $T' => 'sleep ${T}',
    'sleep "$T" x' => 'sleep "${T}" x',
    'sleep ${T:-9}' => 'sleep ${T:-9}',
    'sleep ${#T}' => 'sleep ${#T}',
    'sleep "$@" "$?"' => 'sleep "${@}" "${?}"',
    'sleep $(echo 9)' => 'sleep $(...)',
    'sleep $((1+2))' => 'sleep $((1+2))',
    "sleep 'a b'" => 'sleep "a b"',
    'sleep *.txt' => 'sleep *.txt',
    'sleep 5 | cat' => 'sleep 5 | cat',
    '(sleep 5)' => '(sleep 5)',
    '{ sleep 5; echo x; }' => 'sleep 5; echo x',
    'sleep 5 >/dev/null 2>&1' => 'sleep 5 1>/dev/null 2>&1',
    'sleep 5 <f >>log' => 'sleep 5 0<f 1>>log',
    'X=1 sleep 5' => 'sleep 5',
    'X=1' => 'set',
    'if true; then sleep 1; elif false; then :; else :; fi' =>
      'if true; then sleep 1; else if false; then :; else :; fi; fi',
    'if true; then sleep 1; fi' => 'if true; then sleep 1; fi',
    'while true; do sleep 1; done' => 'while true; do sleep 1; done',
    'until false; do sleep 1; done' => 'until false; do sleep 1; done',
    'for i in 1 2; do sleep 3; done' => 'for i in 1 2; do sleep 3; done',
    'for i; do sleep 3; done' => 'for i in "${@}"; do sleep 3; done',
    'case a in a|b) sleep 5;; *) :;; esac' => 'case a in a) sleep 5;; *) :;; esac',
    'sleep 5 && echo a || echo b' => 'sleep 5 && echo a || echo b',
    '! sleep 5' => '!sleep 5',
    'sleep "x$T.y"' => 'sleep "x${T}.y"',
    "cat <<X\nbody\nX" => 'cat <<...',
    'sleep 2>&1' => 'sleep 2>&1',
    '{ a & b; }' => 'a & b',
    'f() { sleep 5; }' => 'f() { sleep 5; }'
  }.freeze

  canon.each do |source, expected|
    it "renders #{source.inspect} as dash does: #{expected.inspect}" do
      expect(render(source)).to eq(expected)
    end
  end

  it 'renders a compound wrapped in redirects with explicit fds' do
    expect(render('{ sleep 5; } >log')).to eq('sleep 5 1>log')
  end

  it 'rejects an unsupported AST class like the former exact-class table' do
    expect { described_class.render(Rush::AST::Node.new) }
      .to raise_error(KeyError, 'unsupported command-text node: Rush::AST::Node')
  end

  it 'rejects a subclass of a supported node because dispatch stays exact-class' do
    stub_const('Rush::AST::DerivedSimpleCommand', Class.new(Rush::AST::SimpleCommand))
    node = Rush::AST::DerivedSimpleCommand.new([Rush::AST::Word.literal('echo')])
    expect { described_class.render(node) }
      .to raise_error(KeyError, 'unsupported command-text node: Rush::AST::DerivedSimpleCommand')
  end

  it 'rejects a non-heredoc here-doc target instead of treating it as a word' do
    target = Rush::HereDoc.new(delimiter: 'X', quoted: false, strip: false)
    redirect = Rush::AST::Redirect.new(kind: :out, target: target, io_number: nil)
    expect { described_class.redirect(redirect) }
      .to raise_error(TypeError, 'non-heredoc redirect target must be a Word')
  end
end
