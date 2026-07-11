# frozen_string_literal: true

require 'set'
require 'yoshinon'
require 'yuuki/runner'

module Yuuki
  class Caller
    def self.require_dir(require_dir, recursive: false)
      Dir.glob(recursive ? "#{require_dir}/**/*.rb" : "#{require_dir}/*.rb").each { |file| require file }
    end

    def initialize(*instances, use_yoshinon: true)
      @instances = Set.new
      @threads = []
      add(*instances)
      @use_yoshinon = use_yoshinon
    end

    def add(*instances)
      instances.each do |instance|
        if instance.is_a?(Class)
          klass = instance
          raise Yuuki::Error, 'Runner instance must be inherit Yuuki::Runner' unless klass < Yuuki::Runner

          # allocate + explicit initialize so that @yuuki is already set when
          # the runner's #initialize runs
          instance = instance.allocate
          instance.instance_variable_set(:@yuuki, self)
          instance.send(:initialize)
        else
          raise Yuuki::Error, 'Runner instance must be inherit Yuuki::Runner' unless instance.is_a?(Yuuki::Runner)

          instance.instance_variable_set(:@yuuki, self)
        end
        @instances << instance
      end
    end

    # NOTE: intentionally shadows Object#methods; returns [Method, meta] pairs
    # sorted by priority (highest first)
    def methods
      list = @instances.flat_map do |instance|
        methods = instance.class.yuuki_methods
        methods.map { |sig, meta| [instance.method(sig), meta] }
      end
      list.sort_by! { |_method, meta| -(meta[:priority] || 0) }
      list
    end

    def run(*tags, **args, &block)
      selector = proc do |_method, meta|
        meta[:tags] && !(meta[:tags] & tags).empty?
      end
      run_select(selector, **args, &block)
    end

    def run_select(selector, **args, &block)
      run_internal(methods.select(&selector), args, &block)
    end

    def join
      @threads.each(&:join)
      @threads.select!(&:alive?)
    end

    def alive?
      @threads.select!(&:alive?)
      !@threads.empty?
    end
    alias running? alive?

    private

    def run_internal(runners, args, &block)
      @threads.select!(&:alive?)
      runners.each do |method, meta|
        if meta[:thread]
          thread = Thread.new(method, args, block) do |thread_method, thread_args, thread_block|
            run_method_internal(thread_method, thread_args, &thread_block)
          end
          thread.priority = meta[:priority] || 0
          @threads << thread
        else
          run_method_internal(method, args, &block)
        end
      end
    end

    # Maps the args hash onto the method's parameters by name. Positional
    # optionals can only be filled left-to-right: once one is unspecified,
    # passing any later :opt/:rest argument is an error (nonspecified_last_opt).
    def run_method_internal(method, args, &block)
      yoshinon = Yoshinon.lock if @use_yoshinon
      params = method.parameters
      return method[&block] if params.empty?

      params_array = []
      params_hash = {}
      params_block = nil
      nonspecified_last_opt = nil
      params.each do |type, name|
        case type
        when :req
          unless args.key?(name)
            raise Yuuki::Error,
                  "A required argument '#{name}' was not found on running #{method.owner}::#{method.name}"
          end

          params_array << args[name]
        when :opt
          # if parameters do not contain the :opt argument, treat it as not specified
          next nonspecified_last_opt = name unless args.key?(name)

          if nonspecified_last_opt
            # if there already exist non-specified :opt arguments, no more specified :opt argument is allowed
            raise Yuuki::Error, "A required argument '#{nonspecified_last_opt}' was not found " \
                                "on running #{method.owner}::#{method.name}" + " with optional argument '#{name}'"
          end
          params_array << args[name]
        when :rest
          next unless args.key?(name)

          if nonspecified_last_opt
            # if there already exist non-specified :opt arguments, the :rest argument cannot be handled
            raise Yuuki::Error, "A required argument '#{nonspecified_last_opt}' not found " \
                                "on running #{method.owner}::#{method.name}" + " with rest argument '#{name}'"
          end
          if args[name].respond_to?(:to_ary)
            params_array += args[name]
          else
            params_array << args[name]
          end
        when :keyreq
          unless args.key?(name)
            raise Yuuki::Error,
                  "A required key argument '#{name}' was not found on running #{method.owner}::#{method.name}"
          end

          params_hash[name] = args[name]
        when :key
          params_hash[name] = args[name] if args.key?(name)
        when :keyrest
          next unless args.key?(name)

          if args[name].respond_to?(:to_hash)
            params_hash.merge!(args[name])
          else
            params_hash[name] = args[name]
          end
        when :block
          params_block = args[name] if args.key?(name)
        end
      end
      # fall back to the block passed to run unless one was explicitly given via args
      params_block = block unless params.any? { |type, name| type == :block && args.key?(name) }
      params_hash.empty? ? method[*params_array, &params_block] : method[*params_array, **params_hash, &params_block]
    ensure
      yoshinon&.unlock
    end
  end
end
