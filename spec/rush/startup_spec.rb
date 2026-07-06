# frozen_string_literal: true

RSpec.describe Rush::Startup do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def startup(login: false, interactive: false)
    described_class.new(login: login, interactive: interactive).run(executor)
  end

  it 'runs /etc/profile then ~/.profile for a login shell' do
    state.variables.assign('HOME', '/home/test')
    system.provide_file('/etc/profile', "echo etc\n")
    system.provide_file('/home/test/.profile', "echo home\n")
    startup(login: true)
    expect(system.stdout.string).to eq("etc\nhome\n")
  end

  it 'runs nothing for a plain non-login, non-interactive shell' do
    system.provide_file('/etc/profile', "echo etc\n")
    startup
    expect(system.stdout.string).to eq('')
  end

  it 'skips missing files silently' do
    state.variables.assign('HOME', '/home/test')
    startup(login: true, interactive: true)
    expect([system.stdout.string, system.stderr.string]).to eq(['', ''])
  end

  it 'skips ~/.profile when HOME is unset' do
    system.provide_file('/etc/profile', "echo etc\n")
    startup(login: true)
    expect(system.stdout.string).to eq("etc\n")
  end

  it 'runs the parameter-expanded ENV file for an interactive shell' do
    state.variables.assign('HOME', '/home/test')
    state.variables.assign('ENV', '$HOME/envrc')
    system.provide_file('/home/test/envrc', "echo envrc\n")
    startup(interactive: true)
    expect(system.stdout.string).to eq("envrc\n")
  end

  it 'runs the login profiles before the ENV file' do
    state.variables.assign('ENV', '/envrc')
    system.provide_file('/etc/profile', "echo etc\n")
    system.provide_file('/envrc', "echo envrc\n")
    startup(login: true, interactive: true)
    expect(system.stdout.string).to eq("etc\nenvrc\n")
  end

  it 'does not read ENV for a non-interactive shell' do
    state.variables.assign('ENV', '/envrc')
    system.provide_file('/envrc', "echo envrc\n")
    startup(login: true)
    expect(system.stdout.string).to eq('')
  end

  it 'ignores an empty ENV value' do
    state.variables.assign('ENV', '')
    startup(interactive: true)
    expect(system.stdout.string).to eq('')
  end

  it 'persists variables and functions the files define' do
    system.provide_file('/etc/profile', "X=5\ngreet() { echo hi; }\n")
    startup(login: true)
    expect([state.variables.get('X'), state.functions.fetch('greet')]).not_to include(nil)
  end

  it 'bounds a return to its file, leaving its code in $?' do
    state.variables.assign('HOME', '/h')
    system.provide_file('/h/.profile', "echo before\nreturn 3\necho never\n")
    startup(login: true)
    expect([system.stdout.string, state.last_status.exitstatus]).to eq(["before\n", 3])
  end

  it 'lets a syntax error propagate to the session error policy' do
    system.provide_file('/etc/profile', "bad )\n")
    expect { startup(login: true) }.to raise_error(Rush::ParseError)
  end
end
