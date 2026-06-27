# frozen_string_literal: true

RSpec.describe Rush::FunctionTable do
  subject(:table) { described_class.new }

  it 'defines, fetches and reports membership' do
    table.define('f', :body)
    expect([table.fetch('f'), table.key?('f'), table.key?('g')]).to eq([:body, true, false])
  end
end
