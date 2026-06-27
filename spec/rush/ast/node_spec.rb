# frozen_string_literal: true

RSpec.describe Rush::AST::Node do
  it 'requires subclasses to implement #execute' do
    expect { described_class.new.execute(:executor) }.to raise_error(NotImplementedError)
  end
end
