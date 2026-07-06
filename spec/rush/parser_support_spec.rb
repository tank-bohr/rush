# frozen_string_literal: true

RSpec.describe Rush::ParserSupport do
  subject(:parser) { Rush::Parser.new(Rush::Lexer.new('')) }

  def parse(source)
    Rush::Parser.new(Rush::Lexer.new(source)).parse
  end

  def first_command(source)
    parse(source).entries.first.and_or.commands.first
  end

  it 'parses an empty program into an empty list' do
    expect(parse('').entries).to be_empty
  end

  it 'builds and-or, async and sequence entries' do
    list = parse('a && b; c & d')
    expect(list.entries.map(&:async)).to eq([false, true, false])
    expect(list.entries.first.and_or).to be_a(Rush::AST::AndOr)
  end

  it 'partitions assignments, argv words and redirects of a simple command' do
    command = first_command('X=1 echo hi > out')
    expect(command.assignments.map(&:name)).to eq(['X'])
    expect(command.words.map(&:literal_text)).to eq(%w[echo hi])
    expect(command.redirects.map(&:kind)).to eq([:out])
  end

  it 'preserves source order separately from grouped simple-command accessors' do
    command = first_command('> out X=1 echo hi 2> err')
    expect(command.parts).to eq([
                                  command.redirects.fetch(0), command.assignments.fetch(0),
                                  command.words.fetch(0), command.words.fetch(1), command.redirects.fetch(1)
                                ])
  end

  it 'captures an explicit fd as the redirect io_number' do
    expect(first_command('cat 2> err').redirects.first.io_number).to eq(2)
  end

  it 'parses a here-document redirect carrying the collected body' do
    redirect = first_command("cat <<EOF\nhi there\nEOF\n").redirects.first
    expect([redirect.kind, redirect.target.body.literal_text]).to eq([:heredoc, "hi there\n"])
  end

  it 'parses an if clause and a brace group' do
    expect(first_command('if true; then echo hi; fi')).to be_a(Rush::AST::If)
    expect(first_command('{ echo hi; }')).to be_a(Rush::AST::BraceGroup)
  end

  it 'parses a subshell' do
    expect(first_command('(echo hi)')).to be_a(Rush::AST::Subshell)
  end

  it 'parses a negated pipeline' do
    expect(parse('! false').entries.first.and_or.negate).to be(true)
  end

  it 'parses while and until loops' do
    expect(first_command('while true; do :; done')).to be_a(Rush::AST::While)
    expect(first_command('until true; do :; done')).to be_a(Rush::AST::Until)
  end

  it 'parses for loops with and without an in clause' do
    with_in = first_command('for i in a b; do :; done')
    expect([with_in.name, with_in.words.size]).to eq(['i', 2])
    expect(first_command('for i; do :; done').words).to be_nil
  end

  it 'parses a case statement into arms' do
    node = first_command('case x in a) :;; *) :;; esac')
    expect([node.class, node.items.size]).to eq([Rush::AST::Case, 2])
  end

  it 'parses a case whose last item omits ;; before esac (POSIX 2.10.2)' do
    node = first_command('case x in a) :;; *) : ; esac')
    expect([node.class, node.items.size]).to eq([Rush::AST::Case, 2])
  end

  it 'parses a ;;-less last item with an empty list' do
    node = first_command('case x in a) esac')
    expect([node.class, node.items.size]).to eq([Rush::AST::Case, 1])
  end

  it 'parses the optional ( before a case pattern' do
    node = first_command('case x in (a|b) :;; (*) esac')
    expect([node.class, node.items.size]).to eq([Rush::AST::Case, 2])
  end

  it 'rejects a stray esac as a reserved word in command position' do
    expect { first_command('esac') }.to raise_error(Rush::ParseError, /esac/)
  end

  it 'removes a backslash-newline inside a word (POSIX 2.2.1 line continuation)' do
    command = first_command("ec\\\nho joined")
    expect(command.words.map(&:literal_text)).to eq(%w[echo joined])
  end

  it 'removes a backslash-newline between tokens' do
    command = first_command("echo a \\\nb")
    expect(command.words.map(&:literal_text)).to eq(%w[echo a b])
  end

  it 'removes a backslash-newline inside double quotes' do
    command = first_command("echo \"a\\\nb\"")
    expect(command.words.map(&:literal_text)).to eq(%w[echo ab])
  end

  it 'keeps a backslash-newline inside single quotes' do
    command = first_command("echo 'a\\\nb'")
    expect(command.words.last.literal_text).to eq("a\\\nb")
  end

  it 'keeps a backslash that ends the input literal, like dash' do
    command = first_command('echo a\\')
    expect(command.words.map(&:literal_text)).to eq(['echo', 'a\\'])
  end

  it 'parses a function definition' do
    node = first_command('greet() { echo hi; }')
    expect([node.class, node.name]).to eq([Rush::AST::FunctionDef, 'greet'])
  end

  it 'raises a ParseError naming a word value' do
    expect { parser.on_error(0, Rush::AST::Word.literal('oops'), []) }
      .to raise_error(Rush::ParseError, /oops/)
  end

  it 'raises a ParseError naming an operator value' do
    expect { parser.on_error(0, ';', []) }.to raise_error(Rush::ParseError, /;/)
  end

  it 'raises IncompleteInput when the input ends mid-construct' do
    expect { parser.on_error(0, false, []) }.to raise_error(Rush::IncompleteInput)
  end
end
