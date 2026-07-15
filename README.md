# rush

[![CI](https://github.com/tank-bohr/rush/actions/workflows/ci.yml/badge.svg)](https://github.com/tank-bohr/rush/actions/workflows/ci.yml)
[![Gem](https://img.shields.io/gem/v/rush-shell)](https://rubygems.org/gems/rush-shell)

A **POSIX shell written in pure Ruby**. rush implements the POSIX.1-2017 *Shell
Command Language* (IEEE Std 1003.1, §2) to the letter, with **dash** as its
differential oracle: a large corpus of language tests verifies that rush and
`dash -c` produce the same `[stdout, exit status]` byte for byte. Where dash
itself diverges from the standard, the standard wins and the divergence is
documented.

## Install

```sh
gem install rush-shell
```

Ruby >= 3.4 is required (rush is developed and CI-verified on Ruby 4.0). The
gem is `rush-shell`; the executable is `rush`.

## Use

```sh
rush                       # interactive shell
rush -c 'echo hello'       # run a command string
rush script.sh arg1 arg2   # run a script
echo 'ls | wc -l' | rush   # read commands from stdin
```

rush accepts the standard `sh` invocation: `-c`, `-o option`/`+o option`, the
`set`-builtin flag letters (`-e`, `-x`, `-u`, `-m`, …), `--` to end options,
and behaves as a login shell when invoked with a leading-dash `argv[0]`.
Interactive mode (auto-detected on a terminal) has Reline line editing and
full job control: process groups, terminal handover, `Ctrl-Z`, `jobs`, `fg`,
`bg`, and pre-prompt status change reports — matching dash's picture
byte-for-byte in the pty smoke tests. Persistent history and the POSIX `fc`
builtin are on the roadmap.

The full §2 language is implemented: quoting, all parameter-expansion forms,
command substitution, arithmetic expansion, field splitting, pathname
expansion (including bracket expressions and locale collation via glibc),
redirections and here-documents, pipelines and lists, compound commands,
functions, traps, aliases, `getopts`, and the special builtins.

## Why trust a shell?

Correctness in rush is not a claim, it is machinery:

- **Differential testing** — the language corpus runs every case against a
  checksum-pinned dash 0.5.13.4 and compares `[stdout, exit status]`; CI
  repeats this natively and inside a Docker oracle image.
- **2831 examples, ~99.8% line / ~98.8% branch coverage** — irreducible
  fork/exec paths are pinned by out-of-process differential tests instead.
- **Mutation testing** — [mutant](https://github.com/mbj/mutant) over ~38,800
  mutations gates CI at a ratcheted threshold.
- **Two independent type systems** — inline Sorbet `sig {}` and RBS checked by
  Steep, kept deliberately separate so each catches what the other misses.

## Development

```sh
mise install         # Ruby from .tool-versions
bundle install
make install-hooks   # once per clone: Conventional Commits hook (cog)
bundle exec rake     # the full parallel quality gate
```

`bundle exec rake` compiles the Racc parser from `grammar/shell.y`, then runs
rubocop, reek, flay/flog, Steep, Sorbet and the sharded RSpec suite
concurrently. `bin/test-in-docker` runs the same gate plus container-only
smokes against the pinned oracle image. `lib/rush/parser.rb` is generated and
committed; regenerate via `rake compile`, audit with `rake check_parser_drift`.

The architecture is a unidirectional pipeline over shared shell state:

```
Source → Lexer → Racc Parser → AST → Expander → Executor
```

with one feedback wire (the parser nudges lexer state for POSIX grammar rules
1–9) and all OS access funneled through one injectable port
(`Rush::SystemCalls`). Design decisions and per-slice lessons live in
[docs/architecture/](docs/architecture) and [docs/journal.md](docs/journal.md);
agent/contributor workflow lives in [AGENTS.md](AGENTS.md). Notable research:
[Steep vs Sorbet under extreme quality pressure](docs/steep-vs-sorbet.md).

Releases are cut from the `live` branch: semantic-release computes the version
from Conventional Commits and the gem is published to RubyGems via OIDC
trusted publishing with sigstore attestations — no long-lived credentials.

## License

[MIT](LICENSE)
