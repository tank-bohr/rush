# frozen_string_literal: true

RSpec.describe Rush::AST::Redirected do
  let(:system) { FakeSystemCalls.new }

  def run(source)
    Rush::CLI.run(['-c', source], system: system)
  end

  it 'binds an output redirect across every command in the body' do
    run('{ echo a; echo b; } > /out')
    expect(system.files['/out'].string).to eq("a\nb\n")
  end

  it 'redirects a loop body the same way' do
    run('for x in p q; do echo $x; done > /out')
    expect(system.files['/out'].string).to eq("p\nq\n")
  end

  it 'applies several redirects, the last one winning the fd' do
    run('{ echo hi; } > /a > /b')
    expect([system.files['/a'].string, system.files['/b'].string]).to eq(['', "hi\n"])
  end

  it 'does not leak the redirect to later commands' do
    run('{ echo inside; } > /out; echo outside')
    expect(system.files['/out'].string).to eq("inside\n")
    expect(system.stdout.string).to eq("outside\n")
  end

  it 'returns the status of the body' do
    expect(run('{ false; } > /dev/null')).to eq(1)
  end
end
