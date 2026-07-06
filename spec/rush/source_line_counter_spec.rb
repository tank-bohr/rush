# frozen_string_literal: true

RSpec.describe Rush::SourceLineCounter do
  it 'reports the current buffer offset across complete programs' do
    counter = described_class.new
    counter.start("echo one\n")
    expect(counter.offset).to eq(0)
    counter.start("echo two\n")
    expect(counter.offset).to eq(1)
  end

  it 'keeps the original offset while continuation lines accumulate' do
    counter = described_class.new
    counter.start("if true\n")
    counter.continue("then echo ok\n")
    expect(counter.offset).to eq(0)
    counter.start("echo after\n")
    expect(counter.offset).to eq(2)
  end
end
