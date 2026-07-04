# frozen_string_literal: true

RSpec.describe Rush::Scope do
  it 'reports an internal invariant violation before pwd is seeded' do
    scope = described_class.new(Rush::Environment.new({}))
    expect { scope.current_pwd }.to raise_error(Rush::Error, /PWD not seeded/)
  end
end
