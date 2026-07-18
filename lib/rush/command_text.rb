# typed: true
# frozen_string_literal: true

module Rush
  # Renders an AST back into dash's canonical job text — the command column
  # of the jobs listing, fg's echoed line and bg's "[n] ..." (dash's cmdtxt,
  # probed shape by shape off-tty): words re-quoted with double quotes when
  # they carried quoting ($ escaped as \$), parameter expansions always
  # braced (${T}, "${@}", ${T:-9} with the raw default), command
  # substitutions and here-document bodies elided to $(...) and <<...,
  # redirect fds explicit (1>/dev/null, 0<f), assignments dropped from a
  # command that has words — an assignment-only command renders as `set`, a
  # dash quirk kept for parity — group braces dropped, elif spelled as a
  # nested else-if, a negated pipeline prefixed with a spaceless !, and the
  # implicit for-loop list spelled out as in "${@}".
  module CommandText
    extend T::Sig

    sig { params(node: AST::Node).returns(String) }
    def self.render(node)
      Dispatcher.call(node)
    end

    sig { params(node: AST::List).returns(String) }
    def self.list(node)
      node.entries.map { |entry| "#{render(entry.and_or)}#{entry.async ? ' &' : ';'}" }
                  .join(' ').delete_suffix(';')
    end

    sig { params(node: AST::AndOr).returns(String) }
    def self.and_or(node)
      "#{render(node.left)} #{node.op == :and ? '&&' : '||'} #{render(node.right)}"
    end

    sig { params(node: AST::Pipeline).returns(String) }
    def self.pipeline(node)
      "#{'!' if node.negate}#{stages(node.commands)}"
    end

    # A pipeline's stages, also reachable for PipelineRunner's already-split
    # command list (the adopted-job text of a stopped foreground pipeline).
    sig { params(commands: T::Array[AST::Node]).returns(String) }
    def self.stages(commands)
      commands.map { |command| render(command) }.join(' | ')
    end

    sig { params(node: AST::SimpleCommand).returns(String) }
    def self.simple(node)
      words = node.words.map { |word| word(word) }
      words = ['set'] if words.empty?
      (words + node.redirects.map { |redirect| redirect(redirect) }).join(' ')
    end

    sig { params(node: AST::Subshell).returns(String) }
    def self.subshell(node)
      "(#{render(node.body)})"
    end

    sig { params(node: AST::BraceGroup).returns(String) }
    def self.group(node)
      render(node.body)
    end

    sig { params(node: AST::If).returns(String) }
    def self.if_node(node)
      tail = node.alternative ? " else #{render(T.must(node.alternative))};" : ''
      "if #{render(node.condition)}; then #{render(node.consequent)};#{tail} fi"
    end

    sig { params(node: AST::While).returns(String) }
    def self.while_node(node)
      "while #{render(node.condition)}; do #{render(node.body)}; done"
    end

    sig { params(node: AST::Until).returns(String) }
    def self.until_node(node)
      "until #{render(node.condition)}; do #{render(node.body)}; done"
    end

    sig { params(node: AST::For).returns(String) }
    def self.for_node(node)
      list = node.words ? T.must(node.words).map { |word| word(word) }.join(' ') : '"${@}"'
      "for #{node.name} in #{list}; do #{render(node.body)}; done"
    end

    sig { params(node: AST::Case).returns(String) }
    def self.case_node(node)
      items = node.items.map { |item| "#{word(item.patterns.fetch(0))}) #{render(item.body)};;" }
      "case #{word(node.word)} in #{items.join(' ')} esac"
    end

    sig { params(node: AST::FunctionDef).returns(String) }
    def self.function_def(node)
      "#{node.name}() { #{render(node.body)}; }"
    end

    sig { params(node: AST::Redirected).returns(String) }
    def self.redirected(node)
      ([render(node.command)] + node.redirects.map { |redirect| redirect(redirect) }).join(' ')
    end

    # dash prints every fd explicitly (1>/dev/null, 0<f, 2>&1) and elides a
    # here-document to <<... .
    sig { params(redirect: AST::Redirect).returns(String) }
    def self.redirect(redirect)
      return '<<...' if redirect.kind == :heredoc

      target = redirect.target
      raise TypeError, 'non-heredoc redirect target must be a Word' unless target.is_a?(AST::Word)

      op, fd = T.must(OPERATORS[redirect.kind])
      "#{redirect.io_number || fd}#{op}#{word(target)}"
    end

    OPERATORS = T.let({
      in: ['<', 0], out: ['>', 1], append: ['>>', 1], clobber: ['>|', 1],
      readwrite: ['<>', 0], dup_out: ['>&', 1], dup_in: ['<&', 0]
    }.freeze, T::Hash[Symbol, [String, Integer]])

    # Consecutive quoted segments share one pair of double quotes (dash
    # renders "x$T.y" as one quoted run); each segment canonicalises itself
    # (WordSegment#canon).
    sig { params(word: AST::Word).returns(String) }
    def self.word(word)
      runs = word.segments.chunk_while { |left, right| left.quoted == right.quoted }
      runs.map { |run| run_text(run) }.join
    end

    sig { params(run: T::Array[AST::AnySegment]).returns(String) }
    def self.run_text(run)
      body = run.map(&:canon).join
      T.must(run.fetch(0)).quoted ? "\"#{body}\"" : body
    end
  end

  # Correlates each concrete AST node class with CommandText's exact renderer
  # parameter without Method#call's erased return or a broad cast.
  module CommandText
    # Exact-class checks preserve the old TABLE.fetch(node.class) contract.
    class Dispatcher
      extend T::Sig

      sig { params(node: AST::Node).returns(String) }
      def self.call(node)
        sequence_text(node) || compound_text(node) || control_text(node) || case_text(node) ||
          raise(KeyError, "unsupported command-text node: #{node.class}")
      end

      sig { params(node: AST::Node).returns(T.nilable(String)) }
      def self.sequence_text(node)
        return CommandText.list(node) if node.instance_of?(AST::List)
        return CommandText.and_or(node) if node.instance_of?(AST::AndOr)

        CommandText.pipeline(node) if node.instance_of?(AST::Pipeline)
      end

      sig { params(node: AST::Node).returns(T.nilable(String)) }
      def self.compound_text(node)
        return CommandText.simple(node) if node.instance_of?(AST::SimpleCommand)
        return CommandText.subshell(node) if node.instance_of?(AST::Subshell)
        return CommandText.group(node) if node.instance_of?(AST::BraceGroup)
        return CommandText.redirected(node) if node.instance_of?(AST::Redirected)

        CommandText.function_def(node) if node.instance_of?(AST::FunctionDef)
      end

      sig { params(node: AST::Node).returns(T.nilable(String)) }
      def self.control_text(node)
        return CommandText.if_node(node) if node.instance_of?(AST::If)
        return CommandText.while_node(node) if node.instance_of?(AST::While)
        return CommandText.until_node(node) if node.instance_of?(AST::Until)

        CommandText.for_node(node) if node.instance_of?(AST::For)
      end

      sig { params(node: AST::Node).returns(T.nilable(String)) }
      def self.case_text(node)
        CommandText.case_node(node) if node.instance_of?(AST::Case)
      end

      private_class_method :sequence_text, :compound_text, :control_text, :case_text
    end
  end
end
