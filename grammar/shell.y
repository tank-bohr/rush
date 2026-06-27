# rush — POSIX sh grammar (Racc).
#
# Phase 0 is a minimal subset (commands separated by ';' / newline) that proves
# the generate -> commit -> drift-check toolchain end to end. Phase 1 replaces
# the rule section with the full POSIX.1-2017 §2.10 grammar (pipelines, and_or
# lists, compound commands, redirections, function definitions). Action bodies
# stay one-liners that call factory methods in Rush::ParserSupport; no node
# logic, no heredocs/%q in actions (Racc restriction).

class Rush::Parser

token WORD NEWLINE

start program

rule

  program
    : seps_opt                        { result = make_sequence([]) }
    | seps_opt commands seps_opt      { result = make_sequence(val[1]) }
    ;

  commands
    : command                         { result = [val[0]] }
    | commands seps command           { result = val[0] << val[2] }
    ;

  command
    : words                           { result = make_simple_command(val[0]) }
    ;

  words
    : WORD                            { result = [val[0]] }
    | words WORD                      { result = val[0] << val[1] }
    ;

  seps_opt
    :   # empty
    | seps
    ;

  seps
    : sep
    | seps sep
    ;

  sep
    : ';'
    | NEWLINE
    ;

end

---- header

require_relative 'parser_support'

---- inner

include Rush::ParserSupport
