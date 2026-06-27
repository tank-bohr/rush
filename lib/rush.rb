# frozen_string_literal: true

require_relative 'rush/version'
require_relative 'rush/errors'
require_relative 'rush/status'
require_relative 'rush/system_calls'
require_relative 'rush/environment'
require_relative 'rush/shell_state'

require_relative 'rush/ast/node'
require_relative 'rush/ast/word_segment'
require_relative 'rush/ast/word'
require_relative 'rush/ast/simple_command'
require_relative 'rush/ast/sequence'

require_relative 'rush/expansion/pipeline'

require_relative 'rush/builtins/base'
require_relative 'rush/builtins/registry'
require_relative 'rush/builtins/colon'
require_relative 'rush/builtins/true_'
require_relative 'rush/builtins/false_'
require_relative 'rush/builtins/echo'
require_relative 'rush/builtins/exit'
require_relative 'rush/builtins/defaults'

require_relative 'rush/external'
require_relative 'rush/command_runner'
require_relative 'rush/executor'

require_relative 'rush/lexer'
require_relative 'rush/parser_support'
require_relative 'rush/parser'
require_relative 'rush/cli'
