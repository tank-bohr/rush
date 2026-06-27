# frozen_string_literal: true

RSpec.describe Rush::Expansion::TildeExpander do
  subject(:tilde) { described_class.new(executor) }

  let(:env) { Rush::Environment.new('HOME' => '/home/me') }
  let(:system) { FakeSystemCalls.new(homes: { 'bob' => '/home/bob' }) }
  let(:executor) { Rush::Executor.new(system: system, state: Rush::ShellState.new(environment: env)) }

  def seg(value, kind: :literal, quoted: false) = Rush::AST::WordSegment.new(kind: kind, value: value, quoted: quoted)
  def head(value, **) = tilde.expand([seg(value, **)], assignment: false).first.value
  def assigned(value) = tilde.expand([seg(value)], assignment: true).first.value

  it 'expands a bare tilde and ~/path to HOME' do
    expect([head('~'), head('~/foo')]).to eq(['/home/me', '/home/me/foo'])
  end

  it 'expands ~user via the passwd lookup' do
    expect([head('~bob'), head('~bob/x')]).to eq(['/home/bob', '/home/bob/x'])
  end

  it 'leaves an unknown user, a non-leading tilde or a quoted tilde untouched' do
    expect([head('~nobody'), head('a~'), head('~', quoted: true)]).to eq(['~nobody', 'a~', '~'])
  end

  it 'leaves a bare tilde untouched when HOME is unset' do
    state = Rush::ShellState.new(environment: Rush::Environment.new({}))
    bare = described_class.new(Rush::Executor.new(system: system, state: state))
    expect(bare.expand([seg('~')], assignment: false).first.value).to eq('~')
  end

  it 'does not touch a word whose first segment is not an unquoted literal' do
    expect(tilde.expand([seg('x', kind: :param)], assignment: false).first.kind).to eq(:param)
    expect(tilde.expand([], assignment: false)).to eq([])
  end

  it 'expands after each colon only in assignment context' do
    expect([assigned('~/a:~bob:c'), head('~/a:~bob')]).to eq(['/home/me/a:/home/bob:c', '/home/me/a:~bob'])
  end
end
