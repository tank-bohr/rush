# typed: true
# frozen_string_literal: true

module Rush
  # Parses and formats `umask` modes. Symbolic operands describe the permissions
  # that remain allowed (the complement of the creation mask), matching dash and
  # POSIX `umask -S` output.
  class UmaskMode
    extend T::Sig

    CLASSES = T.let({ 'u' => 6, 'g' => 3, 'o' => 0 }.freeze, T::Hash[String, Integer])
    PERMISSIONS = T.let({ 'r' => 4, 'w' => 2, 'x' => 1 }.freeze, T::Hash[String, Integer])
    WHO = T.let((CLASSES.keys + ['a']).freeze, T::Array[String])
    OPERATORS = T.let({ '+' => :add_allowed, '-' => :remove_allowed, '=' => :assign_allowed }.freeze,
                      T::Hash[String, Symbol])
    ALL = T.let(0o777, Integer)

    sig { params(mask: Integer).returns(String) }
    def self.format_octal(mask)
      format('%04o', mask & ALL)
    end

    sig { params(mask: Integer).returns(String) }
    def self.format_symbolic(mask)
      allowed = (~mask) & ALL
      CLASSES.map { |name, shift| "#{name}=#{letters((allowed >> shift) & 7)}" }.join(',')
    end

    sig { params(text: String, current: Integer).returns(T.nilable(Integer)) }
    def self.parse(text, current)
      return parse_octal(text) if text.match?(/\A[0-7]+\z/)

      new(current).parse_symbolic(text)
    end

    sig { params(bits: Integer).returns(String) }
    def self.letters(bits)
      PERMISSIONS.filter_map { |letter, value| letter if bits.anybits?(value) }.join
    end

    sig { params(text: String).returns(Integer) }
    def self.parse_octal(text)
      text.to_i(8) & ALL
    end

    sig { params(current: Integer).void }
    def initialize(current)
      @allowed = T.let((~current) & ALL, Integer)
    end

    sig { params(text: String).returns(T.nilable(Integer)) }
    def parse_symbolic(text)
      text.split(',', -1).each { |clause| apply_clause(clause) }
      (~@allowed) & ALL
    rescue ArgumentError
      nil
    end

    private

    sig { params(clause: String).void }
    def apply_clause(clause)
      who, rest = split_who(clause)
      operator = rest.slice!(0)
      raise ArgumentError unless operator && OPERATORS.key?(operator)

      apply(operator, target_mask(who), permission_bits(rest, who))
    end

    # Duplicate who letters (uua+w) need no dedup: every consumer ORs the
    # per-class bit fields, so repeats are absorbed (mutant-verified).
    sig { params(clause: String).returns([T::Array[String], String]) }
    def split_who(clause)
      who = [] #: Array[String]
      who.concat(expand_who(T.must(clause.slice!(0)))) while WHO.any? { |name| clause.start_with?(name) }
      [who.empty? ? CLASSES.keys : who, clause]
    end

    sig { params(name: String).returns(T::Array[String]) }
    def expand_who(name)
      name == 'a' ? CLASSES.keys : [name]
    end

    sig { params(operator: String, target: Integer, bits: Integer).void }
    def apply(operator, target, bits)
      method(OPERATORS.fetch(operator)).call(target, bits)
    end

    sig { params(target: Integer, bits: Integer).void }
    def assign_allowed(target, bits)
      @allowed = (@allowed & ~target) | bits
    end

    sig { params(_target: Integer, bits: Integer).void }
    def add_allowed(_target, bits)
      @allowed |= bits
    end

    sig { params(_target: Integer, bits: Integer).void }
    def remove_allowed(_target, bits)
      @allowed &= ~bits
    end

    sig { params(who: T::Array[String]).returns(Integer) }
    def target_mask(who)
      who.reduce(0) { |mask, name| mask | (7 << CLASSES.fetch(name)) }
    end

    sig { params(text: String, who: T::Array[String]).returns(Integer) }
    def permission_bits(text, who)
      text.each_char.reduce(0) { |bits, char| bits | bits_for(char, who) }
    end

    sig { params(char: String, who: T::Array[String]).returns(Integer) }
    def bits_for(char, who)
      return permission_value(char, who) if PERMISSIONS.key?(char)
      return copy_value(char, who) if CLASSES.key?(char)

      raise ArgumentError
    end

    sig { params(char: String, who: T::Array[String]).returns(Integer) }
    def permission_value(char, who)
      value = PERMISSIONS.fetch(char)
      who.reduce(0) { |bits, name| bits | (value << CLASSES.fetch(name)) }
    end

    sig { params(char: String, who: T::Array[String]).returns(Integer) }
    def copy_value(char, who)
      source = (@allowed >> CLASSES.fetch(char)) & 7
      who.reduce(0) { |bits, name| bits | (source << CLASSES.fetch(name)) }
    end
  end
end
