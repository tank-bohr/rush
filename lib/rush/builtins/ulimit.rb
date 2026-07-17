# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # One ulimit resource: option flag, dash list label, SystemCalls key, and display/set scale.
    UlimitResource = Data.define(:flag, :label, :resource, :scale)
    # Parsed ulimit invocation: list-all flag, selected resource/limit side, and optional value.
    UlimitRequest = Data.define(:all, :resource, :target, :explicit_target, :value)
    # Parser error code plus optional option text for diagnostics.
    UlimitParseError = Data.define(:kind, :detail)
    ULIMIT_RESOURCE_LIST = T.let([
      UlimitResource.new('t', 'time(seconds)', :cpu, 1),
      UlimitResource.new('f', 'file(blocks)', :fsize, 512),
      UlimitResource.new('d', 'data(kbytes)', :data, 1024),
      UlimitResource.new('s', 'stack(kbytes)', :stack, 1024),
      UlimitResource.new('c', 'coredump(blocks)', :core, 512),
      UlimitResource.new('m', 'memory(kbytes)', :rss, 1024),
      UlimitResource.new('l', 'locked memory(kbytes)', :memlock, 1024),
      UlimitResource.new('p', 'process', :nproc, 1),
      UlimitResource.new('n', 'nofiles', :nofile, 1),
      UlimitResource.new('v', 'vmemory(kbytes)', :as, 1024),
      UlimitResource.new('w', 'locks', :locks, 1),
      UlimitResource.new('r', 'rtprio', :rtprio, 1)
    ].freeze, T::Array[UlimitResource])
    ULIMIT_RESOURCES = T.let(
      ULIMIT_RESOURCE_LIST.to_h { |resource| [resource.flag, resource] }.freeze,
      T::Hash[String, UlimitResource]
    )
    ULIMIT_DEFAULT_RESOURCE = T.let(ULIMIT_RESOURCES.fetch('f'), UlimitResource)
    ULIMIT_TARGETS = T.let({ 'H' => :hard, 'S' => :soft }.freeze, T::Hash[String, Symbol])

    # Typed mutable state while a compact ulimit option cluster is folded.
    class UlimitOptionState
      extend T::Sig

      sig { returns(T::Boolean) }
      attr_reader :all

      sig { returns(UlimitResource) }
      attr_reader :resource

      sig { returns(Symbol) }
      attr_reader :target

      sig { returns(T::Boolean) }
      attr_reader :explicit_target

      sig { params(default: UlimitResource).void }
      def initialize(default)
        @all = T.let(false, T::Boolean)
        @resource = T.let(default, UlimitResource)
        @target = T.let(:soft, Symbol)
        @explicit_target = T.let(false, T::Boolean)
      end

      sig { void }
      def select_all
        @all = true
      end

      sig { params(resource: UlimitResource).void }
      def select_resource(resource)
        @resource = resource
      end

      sig { params(target: Symbol).void }
      def select_target(target)
        @target = target
        @explicit_target = true
      end

      sig { params(value: T.nilable(String)).returns(UlimitRequest) }
      def request(value)
        UlimitRequest.new(all, resource, target, explicit_target, value)
      end
    end

    # Mutable parser for ulimit's compact option clusters (`-Hn`, `-Sn`, `-a`).
    # It returns either a UlimitRequest or a small parse-error value that the
    # builtin turns into the user-facing diagnostic.
    class UlimitRequestBuilder
      extend T::Sig

      sig { params(resources: T::Hash[String, UlimitResource], default: UlimitResource).void }
      def initialize(resources, default)
        @resources = resources
        @state = T.let(UlimitOptionState.new(default), UlimitOptionState)
      end

      sig { params(args: T::Array[String]).returns(T.any(UlimitRequest, UlimitParseError)) }
      def call(args)
        rest = args.dup
        value = extract_value(rest)
        return error(:too_many) if rest.any? { |arg| !arg.start_with?('-') }

        parse_options(rest, value)
      end

      private

      sig { params(args: T::Array[String]).returns(T.nilable(String)) }
      def extract_value(args)
        last = args.last
        args.pop if last && !last.start_with?('-')
      end

      sig { params(args: T::Array[String], value: T.nilable(String)).returns(T.any(UlimitRequest, UlimitParseError)) }
      def parse_options(args, value)
        option_failure = option_error(args)
        return option_failure if option_failure
        return error(:too_many) if @state.all && value

        request(value)
      end

      sig { params(args: T::Array[String]).returns(T.nilable(UlimitParseError)) }
      def option_error(args)
        args.each do |arg|
          argument_failure = apply(arg)
          return argument_failure if argument_failure
        end
        nil
      end

      sig { params(arg: String).returns(T.nilable(UlimitParseError)) }
      def apply(arg)
        return error(:illegal_option, arg) if arg == '-'

        apply_flags(arg.delete_prefix('-'))
      end

      sig { params(flags: String).returns(T.nilable(UlimitParseError)) }
      def apply_flags(flags)
        flags.each_char do |flag|
          flag_failure = apply_or_error(flag)
          return flag_failure if flag_failure
        end
        nil
      end

      sig { params(flag: String).returns(T::Boolean) }
      def known_flag?(flag)
        flag == 'a' || @resources.key?(flag) || ULIMIT_TARGETS.key?(flag)
      end

      sig { params(flag: String).returns(T.nilable(UlimitParseError)) }
      def apply_or_error(flag)
        return return_error(flag) unless known_flag?(flag)

        apply_flag(flag)
        nil
      end

      sig { params(flag: String).returns(UlimitParseError) }
      def return_error(flag)
        error(:illegal_option, "-#{flag}")
      end

      sig { params(flag: String).void }
      def apply_flag(flag)
        @state.select_all if flag == 'a'
        @state.select_resource(@resources.fetch(flag)) if @resources.key?(flag)
        apply_target(flag) if ULIMIT_TARGETS.key?(flag)
      end

      sig { params(flag: String).void }
      def apply_target(flag)
        @state.select_target(ULIMIT_TARGETS.fetch(flag))
      end

      sig { params(value: T.nilable(String)).returns(UlimitRequest) }
      def request(value)
        @state.request(value)
      end

      sig { params(kind: Symbol, detail: T.nilable(String)).returns(UlimitParseError) }
      def error(kind, detail = nil)
        UlimitParseError.new(kind, detail)
      end
    end

    # `ulimit [-H|-S] [-a|-resource] [limit]` — query or set process resource
    # limits. Values are printed in dash/POSIX units (blocks or kbytes for byte
    # resources); `unlimited` maps to the platform's infinity value.
    class Ulimit < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        request = parse_request
        return parse_error(request) if request.is_a?(UlimitParseError)

        run_request(request)
      end

      private

      sig { returns(T.any(UlimitRequest, UlimitParseError)) }
      def parse_request
        UlimitRequestBuilder.new(ULIMIT_RESOURCES, ULIMIT_DEFAULT_RESOURCE).call(operands)
      end

      sig { params(error: UlimitParseError).returns(Status) }
      def parse_error(error)
        return too_many if error.kind == :too_many

        illegal_option(T.must(error.detail))
      end

      sig { params(request: UlimitRequest).returns(Status) }
      def run_request(request)
        return list_all(request) if request.all
        return change_limit(request) if request.value

        print_limit(request.resource, request.target)
      end

      sig { params(request: UlimitRequest).returns(Status) }
      def list_all(request)
        ULIMIT_RESOURCE_LIST.each { |resource| print_list_entry(resource, request.target) }
        success
      end

      sig { params(resource: UlimitResource, target: Symbol).void }
      def print_list_entry(resource, target)
        stdout.printf("%<label>-20s %<value>s\n", label: resource.label, value: limit_text(resource, target))
      end

      sig { params(request: UlimitRequest).returns(Status) }
      def change_limit(request)
        value = parse_value(T.must(request.value), request.resource)
        return value if value.is_a?(Status)

        apply_limit(request, value)
      end

      sig { params(request: UlimitRequest, value: Integer).returns(Status) }
      def apply_limit(request, value)
        limits = limits_for(request, value)
        executor.system.setrlimit(request.resource.resource, limits.fetch(0), limits.fetch(1))
        success
      rescue SystemCallError, ArgumentError
        limit_error
      end

      sig { params(request: UlimitRequest, value: Integer).returns([Integer, Integer]) }
      def limits_for(request, value)
        soft, hard = executor.system.getrlimit(request.resource.resource)
        limits_for_set(request, value, soft, hard)
      end

      sig do
        params(request: UlimitRequest, value: Integer, soft: Integer, hard: Integer).returns([Integer, Integer])
      end
      def limits_for_set(request, value, soft, hard)
        return [value, hard] if request.explicit_target && request.target == :soft
        return [soft, value] if request.explicit_target && request.target == :hard

        [value, value]
      end

      sig { params(resource: UlimitResource, target: Symbol).returns(Status) }
      def print_limit(resource, target)
        stdout.puts(limit_text(resource, target))
        success
      end

      sig { params(resource: UlimitResource, target: Symbol).returns(String) }
      def limit_text(resource, target)
        soft, hard = executor.system.getrlimit(resource.resource)
        format_limit(target == :hard ? hard : soft, resource)
      end

      sig { params(text: String, resource: UlimitResource).returns(T.any(Integer, Status)) }
      def parse_value(text, resource)
        return executor.system.infinity_limit if text == 'unlimited'
        return Integer(text, 10) * resource.scale if text.match?(/\A\d+\z/)

        illegal_number(text)
      end

      sig { params(value: Integer, resource: UlimitResource).returns(String) }
      def format_limit(value, resource)
        return 'unlimited' if value >= executor.system.infinity_limit

        (value / resource.scale).to_s
      end

      sig { returns(Status) }
      def limit_error
        stderr.puts('rush: ulimit: error setting limit')
        failure(2)
      end

      sig { returns(Status) }
      def too_many
        stderr.puts('rush: ulimit: too many arguments')
        failure(2)
      end

      sig { params(option: String).returns(Status) }
      def illegal_option(option)
        stderr.puts("rush: ulimit: Illegal option #{option}")
        failure(2)
      end

      sig { params(text: String).returns(Status) }
      def illegal_number(text)
        stderr.puts("rush: ulimit: Illegal number: #{text}")
        failure(2)
      end
    end
  end
end
