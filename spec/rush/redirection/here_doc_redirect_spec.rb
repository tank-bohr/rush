# frozen_string_literal: true

RSpec.describe Rush::Redirection::HereDocRedirect do
  let(:system) { FakeSystemCalls.new }
  let(:io) { Rush::IoTable.standard(system) }

  def redirect(io_number)
    Rush::AST::Redirect.new(kind: :heredoc, target: nil, io_number: io_number)
  end

  it 'binds the body to stdin as a readable stream' do
    result = described_class.new.apply(redirect(nil), "body\n", io, system)
    expect([result.get(0).read, result.entry(0).owned?]).to eq(["body\n", true])
  end

  it 'honours an explicit fd' do
    result = described_class.new.apply(redirect(3), 'x', io, system)
    expect([result.get(3).read, result.entry(3).owned?]).to eq(['x', true])
  end
end
