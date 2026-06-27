# rush — POSIX sh grammar (Racc), transcribed from POSIX.1-2017 §2.10.2.
#
# Phase 1: lists / and_or / pipelines (with ! negation) / simple commands with
# assignments and file redirections / multi-stage pipes, plus the `if` compound
# command and brace groups. for/while/until/case, subshells and functions arrive
# in later slices. Action bodies are one-liners calling Rush::ParserSupport
# factories; the grammar currently compiles with zero conflicts.

class Rush::Parser

token WORD ASSIGNMENT_WORD IO_NUMBER NEWLINE
token AND_IF OR_IF
token DGREAT LESSGREAT CLOBBER
token If Then Else Elif Fi Lbrace Rbrace Bang
token While Until Do Done

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

  pipeline
    : pipe_sequence                               { result = make_pipeline(val[0], false) }
    | Bang pipe_sequence                          { result = make_pipeline(val[1], true) }
    ;

  pipe_sequence
    : command                                     { result = [val[0]] }
    | pipe_sequence '|' linebreak command         { result = val[0] << val[3] }
    ;

  command
    : simple_command                              { result = val[0] }
    | compound_command                            { result = val[0] }
    ;

  compound_command
    : brace_group                                 { result = val[0] }
    | if_clause                                   { result = val[0] }
    | while_clause                                { result = val[0] }
    | until_clause                                { result = val[0] }
    ;

  brace_group
    : Lbrace compound_list Rbrace                 { result = make_brace_group(val[1]) }
    ;

  while_clause
    : While compound_list do_group                { result = make_while(val[1], val[2]) }
    ;

  until_clause
    : Until compound_list do_group                { result = make_until(val[1], val[2]) }
    ;

  do_group
    : Do compound_list Done                       { result = val[1] }
    ;

  if_clause
    : If compound_list Then compound_list else_part Fi { result = make_if(val[1], val[3], val[4]) }
    | If compound_list Then compound_list Fi           { result = make_if(val[1], val[3], nil) }
    ;

  else_part
    : Elif compound_list Then compound_list                { result = make_if(val[1], val[3], nil) }
    | Elif compound_list Then compound_list else_part      { result = make_if(val[1], val[3], val[4]) }
    | Else compound_list                                   { result = val[1] }
    ;

  compound_list
    : linebreak term                              { result = make_list(val[1]) }
    | linebreak term separator                    { result = make_list(terminate_list(val[1], val[2])) }
    ;

  term
    : term separator and_or                       { result = append_and_or(val[0], val[1], val[2]) }
    | and_or                                      { result = [pending_entry(val[0])] }
    ;

  separator
    : separator_op linebreak                      { result = val[0] }
    | newline_list                                { result = ';' }
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
