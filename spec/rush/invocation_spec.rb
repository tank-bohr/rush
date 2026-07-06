# frozen_string_literal: true

RSpec.describe Rush::Invocation do
  def invocation(argv, system: FakeSystemCalls.new)
    described_class.new(argv, system)
  end

  describe '-c command source' do
    it 'takes the command string, command name and positionals from the operands' do
      inv = invocation(['-c', 'echo hi', 'name', 'a', 'b'])
      expect([inv.source, inv.name, inv.positionals]).to eq(['echo hi', 'name', %w[a b]])
    end

    it 'defaults the shell name when no command_name operand is given' do
      inv = invocation(['-c', 'echo hi'])
      expect([inv.name, inv.positionals]).to eq(['rush', []])
    end

    it 'requires a command string operand' do
      expect { invocation(['-c']).source }
        .to raise_error(Rush::InvocationError, '-c requires an argument')
    end

    it 'rejects +c' do
      expect { invocation(['+c', 'echo hi']) }
        .to raise_error(Rush::InvocationError, 'Illegal option +c')
    end
  end

  describe 'script-file source' do
    it 'reads the file, using its path as $0 and later operands as positionals' do
      system = FakeSystemCalls.new
      system.provide_file('run.sh', "echo hi\n")
      inv = invocation(['run.sh', 'x'], system: system)
      expect([inv.source, inv.name, inv.positionals]).to eq(["echo hi\n", 'run.sh', ['x']])
    end

    it 'reports an unreadable file as an invocation error' do
      expect { invocation(['missing.sh']).source }
        .to raise_error(Rush::InvocationError, /cannot open missing\.sh/)
    end

    it 'treats operands after -- as the script file, not options' do
      system = FakeSystemCalls.new
      system.provide_file('-c', "echo dashc\n")
      inv = invocation(['--', '-c'], system: system)
      expect([inv.source, inv.name]).to eq(["echo dashc\n", '-c'])
    end

    it 'lets +s with an operand fall through to the script file' do
      system = FakeSystemCalls.new
      system.provide_file('run.sh', "echo hi\n")
      inv = invocation(['+s', 'run.sh'], system: system)
      expect([inv.source, inv.shell_flags.fetch(:stdin)]).to eq(["echo hi\n", false])
    end
  end

  describe 'stdin source' do
    it 'reads stdin with no operands, keeping the default name' do
      inv = invocation([], system: FakeSystemCalls.new(stdin: "echo hi\n"))
      expect([inv.source, inv.name, inv.positionals]).to eq(["echo hi\n", 'rush', []])
    end

    it 'keeps reading stdin under -s, turning operands into positionals' do
      inv = invocation(['-s', 'a', 'b'], system: FakeSystemCalls.new(stdin: "echo hi\n"))
      expect([inv.source, inv.name, inv.positionals]).to eq(["echo hi\n", 'rush', %w[a b]])
    end
  end

  describe 'option flags' do
    it 'maps set-builtin letters onto shell flags' do
      expect(invocation(['-e', '-c', ':']).shell_flags).to include(errexit: true)
    end

    it 'parses clustered letters' do
      expect(invocation(['-eu', '-c', ':']).shell_flags).to include(errexit: true, nounset: true)
    end

    it 'parses -c clustered with option letters' do
      inv = invocation(['-ec', 'echo hi'])
      expect([inv.source, inv.shell_flags.fetch(:errexit)]).to eq(['echo hi', true])
    end

    it 'lets a later + cluster switch an option back off' do
      expect(invocation(['-e', '+e', '-c', ':']).shell_flags).to include(errexit: false)
    end

    it 'accepts the -o long form' do
      expect(invocation(['-o', 'errexit', '-c', ':']).shell_flags).to include(errexit: true)
    end

    it 'requires an argument for -o' do
      expect { invocation(['-o']) }
        .to raise_error(Rush::InvocationError, '-o requires an argument')
    end

    it 'rejects an unknown -o name' do
      expect { invocation(['-o', 'bogus']) }
        .to raise_error(Rush::InvocationError, 'Illegal option -o bogus')
    end

    it 'rejects an unknown option letter' do
      expect { invocation(['-q']) }
        .to raise_error(Rush::InvocationError, 'Illegal option -q')
    end
  end

  describe 'interactivity' do
    it 'is interactive with no operands when stdin and stderr are both ttys' do
      inv = invocation([], system: FakeSystemCalls.new(tty: true))
      expect([inv.interactive?, inv.repl?]).to eq([true, true])
    end

    it 'is not interactive when only stdin is a tty' do
      inv = invocation([], system: FakeSystemCalls.new(tty: true, stderr_tty: false))
      expect(inv.interactive?).to be(false)
    end

    it 'is not interactive when stdin is not a tty' do
      expect(invocation([]).interactive?).to be(false)
    end

    it 'is not interactive on a terminal once -c is given' do
      inv = invocation(['-c', ':'], system: FakeSystemCalls.new(tty: true))
      expect(inv.interactive?).to be(false)
    end

    it 'is not interactive on a terminal once a script operand is given' do
      inv = invocation(['run.sh'], system: FakeSystemCalls.new(tty: true))
      expect(inv.interactive?).to be(false)
    end

    it 'is forced interactive by -i even without a terminal' do
      inv = invocation(['-i'])
      expect([inv.interactive?, inv.repl?]).to eq([true, true])
    end

    it 'is forced non-interactive by +i even on a terminal' do
      inv = invocation(['+i'], system: FakeSystemCalls.new(tty: true))
      expect(inv.interactive?).to be(false)
    end

    it 'runs -i -c as an interactive-flagged batch, not a REPL' do
      inv = invocation(['-i', '-c', ':'])
      expect([inv.interactive?, inv.repl?]).to eq([true, false])
    end
  end

  describe 'login shells' do
    it 'is not a login shell by default' do
      expect(invocation(['-c', ':']).login?).to be(false)
    end

    it 'is a login shell under -l' do
      expect(invocation(['-l', '-c', ':']).login?).to be(true)
    end

    it 'is a login shell when the program name begins with -' do
      inv = invocation(['-c', ':'], system: FakeSystemCalls.new(program_name: '-rush'))
      expect(inv.login?).to be(true)
    end

    it 'lets +l override a login program name' do
      inv = invocation(['+l', '-c', ':'], system: FakeSystemCalls.new(program_name: '-rush'))
      expect(inv.login?).to be(false)
    end
  end

  describe '#shell_flags implicit flags' do
    it 'marks a stdin source with s and an interactive session with i' do
      inv = invocation(['-i'])
      expect(inv.shell_flags).to include(stdin: true, interactive: true)
    end

    it 'marks a plain batch as stdin but not interactive' do
      expect(invocation([]).shell_flags).to include(stdin: true, interactive: false)
    end

    it 'marks -c as neither stdin nor interactive' do
      expect(invocation(['-c', ':']).shell_flags).to include(stdin: false, interactive: false)
    end
  end
end
