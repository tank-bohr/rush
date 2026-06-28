# frozen_string_literal: true

RSpec.describe Rush::Expansion::TildeExpander do
  let(:env) { Rush::Environment.new('HOME' => '/home/me') }
  let(:system) { FakeSystemCalls.new(homes: { 'bob' => '/home/bob' }) }
  let(:executor) { Rush::Executor.new(system: system, state: Rush::ShellState.new(environment: env)) }

  def seg(value, kind: :literal, quoted: false)
    { literal: Rush::AST::LiteralSegment, param: Rush::AST::ParamSegment }.fetch(kind).new(value, quoted)
  end

  def head(value, **) = described_class.new(executor, [seg(value, **)]).expand.first.value
  def assigned(value) = Rush::Expansion::AssignmentTilde.new(executor, [seg(value)]).expand.first.value

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
    bare = described_class.new(Rush::Executor.new(system: system, state: state), [seg('~')])
    expect(bare.expand.first.value).to eq('~')
  end

  it 'does not touch a word whose first segment is not an unquoted literal' do
    expect(described_class.new(executor, [seg('x', kind: :param)]).expand.first).to be_a(Rush::AST::ParamSegment)
    expect(described_class.new(executor, []).expand).to eq([])
  end

  it 'expands after each colon only in assignment context' do
    expect([assigned('~/a:~bob:c'), head('~/a:~bob')]).to eq(['/home/me/a:/home/bob:c', '/home/me/a:~bob'])
  end

  it 'NoTilde passes the segments through unchanged' do
    segments = [seg('~/foo')]
    expect(Rush::Expansion::NoTilde.new(executor, segments).expand).to eq(segments)
  end
end
