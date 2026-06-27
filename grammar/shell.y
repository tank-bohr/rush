# rush — POSIX sh grammar (Racc), transcribed from POSIX.1-2017 §2.10.2.
#
# Phase 1 Slice 1: lists / and_or / pipelines / simple commands with
# assignments and file redirections. Here-documents, reserved words and compound
# commands (if/while/until/for/case, subshell, brace group, functions) arrive in
# later slices with the context-sensitive lexer (POSIX Grammar Rules 1,3-9).
# Action bodies are one-liners calling factory methods in Rush::ParserSupport.

class Rush::Parser

token WORD ASSIGNMENT_WORD IO_NUMBER NEWLINE
token AND_IF OR_IF
token DGREAT LESSGREAT CLOBBER

start program

rule

  program
    : linebreak                                   { result = make_list([]) }
    | linebreak complete_commands linebreak       { result = make_list(val[1]) }
    ;

  complete_commands
    : complete_command                            { result = val[0] }
    | complete_commands newline_list complete_command { result = val[0] + val[2] }
    ;

  complete_command
    : list separator_op                           { result = terminate_list(val[0], val[1]) }
    | list                                        { result = terminate_list(val[0], ';') }
    ;

  list
    : list separator_op and_or                    { result = append_and_or(val[0], val[1], val[2]) }
    | and_or                                      { result = [pending_entry(val[0])] }
    ;

  and_or
    : pipeline                                    { result = val[0] }
    | and_or AND_IF linebreak pipeline            { result = make_and_or(val[0], :and, val[3]) }
    | and_or OR_IF linebreak pipeline             { result = make_and_or(val[0], :or, val[3]) }
    ;

  # Multi-stage pipelines (the `pipe_sequence '|' ...` production) and the
  # PipelineRunner that forks their stages arrive in the fork slice; for now a
  # pipeline is a single command.
  pipeline
    : pipe_sequence                               { result = make_pipeline(val[0]) }
    ;

  pipe_sequence
    : command                                     { result = [val[0]] }
    ;

  command
    : simple_command                              { result = val[0] }
    ;

  simple_command
    : cmd_prefix cmd_word cmd_suffix              { result = make_simple_command(val[0], val[1], val[2]) }
    | cmd_prefix cmd_word                         { result = make_simple_command(val[0], val[1], []) }
    | cmd_prefix                                  { result = make_simple_command(val[0], nil, []) }
    | cmd_name cmd_suffix                         { result = make_simple_command([], val[0], val[1]) }
    | cmd_name                                    { result = make_simple_command([], val[0], []) }
    ;

  cmd_name
    : WORD                                        { result = val[0] }
    ;

  cmd_word
    : WORD                                        { result = val[0] }
    ;

  cmd_prefix
    : io_redirect                                 { result = [val[0]] }
    | cmd_prefix io_redirect                      { result = val[0] << val[1] }
    | ASSIGNMENT_WORD                             { result = [val[0]] }
    | cmd_prefix ASSIGNMENT_WORD                  { result = val[0] << val[1] }
    ;

  cmd_suffix
    : io_redirect                                 { result = [val[0]] }
    | cmd_suffix io_redirect                      { result = val[0] << val[1] }
    | WORD                                        { result = [val[0]] }
    | cmd_suffix WORD                             { result = val[0] << val[1] }
    ;

  io_redirect
    : io_file                                     { result = val[0] }
    | IO_NUMBER io_file                           { result = with_io_number(val[1], val[0]) }
    ;

  # Dup/close redirections (<&, >&, N>&-) arrive with the fd-management slice.
  io_file
    : '<' filename                                { result = make_redirect(:in, val[1]) }
    | '>' filename                                { result = make_redirect(:out, val[1]) }
    | DGREAT filename                             { result = make_redirect(:append, val[1]) }
    | LESSGREAT filename                          { result = make_redirect(:readwrite, val[1]) }
    | CLOBBER filename                            { result = make_redirect(:clobber, val[1]) }
    ;

  filename
    : WORD                                        { result = val[0] }
    ;

  separator_op
    : '&'                                         { result = '&' }
    | ';'                                         { result = ';' }
    ;

  newline_list
    : NEWLINE
    | newline_list NEWLINE
    ;

  linebreak
    : newline_list
    |   # empty
    ;

end

---- header

require_relative 'parser_support'

---- inner

include Rush::ParserSupport
