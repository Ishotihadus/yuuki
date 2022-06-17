# frozen_string_literal: true

require 'set'
require 'yuuki/runner'
require 'yoshinon'

module Yuuki
  class Caller
    # requires all the rb files in the given directory
    # @param [String] require_dir directory
    # @param [Boolean] recursive
    def self.require_dir(require_dir, recursive: false)
      Dir.glob(recursive ? "#{require_dir}/**/*.rb" : "#{require_dir}/*.rb").sort.each {|file| require file}
    end

    # @param [Object] instances
    def initialize(*instances, use_yoshinon: true)
      @instances = Set.new
      @threads = []
      add(*instances)
      @use_yoshinon = use_yoshinon
    end

    # adds instances to yuuki
    # @param [Object] instances
    def add(*instances)
      instances.each do |instance|
        # create instance if class is given
        if instance.is_a?(Class)
          klass = instance
          # check the klass is extended
          unless klass.singleton_class.include?(Yuuki::Runner)
            raise Yuuki::Error, 'Runner instance must be extend Yuuki::Runner'
          end

          instance = instance.allocate
          instance.instance_variable_set(:@yuuki, self)
          instance.send(:initialize)
        else
          # check the klass is extended
          unless instance.class.singleton_class.include?(Yuuki::Runner)
            raise Yuuki::Error, 'Runner instance must be extend Yuuki::Runner'
          end

          # add @yuuki to the instance
          instance.instance_variable_set(:@yuuki, self)
        end

        # regist
        @instances << instance
      end
    end

    # returns runners
    # @return [Array<[Method, Hash<Symbol, Object>]>]
    def runners
      list = @instances.flat_map do |instance|
        methods = instance.class.instance_variable_get(:@yuuki_methods)
        methods.select {|_sig, meta| meta[:enabled]}.map {|sig, meta| [instance.method(sig), meta]}
      end
      list.sort_by {|_method, meta| -(meta[:priority] || 0)}
    end

    # returns all tags defined as Set
    def tags
      tags = @instances.flat_map do |instance|
        methods = instance.class.instance_variable_get(:@yuuki_methods)
        methods.select {|_sig, meta| meta[:enabled]}.flat_map {|_sig, meta| meta[:tags]}
      end
      ret = Set.new
      tags.each {|e| ret += e if e}
      ret
    end

    # runs all methods
    # @param [Object] args arguments
    def run(**args, &block)
      run_internal(runners, args, &block)
    end

    # runs all selected methods
    # @param [Proc] proc_select
    # @param [Object] args arguments
    def run_select(proc_select, **args, &block)
      run_internal(runners.select(&proc_select), args, &block)
    end

    # set whether to ignore ``tag not associated'' error
    def ignore_tag_error(enabled: true)
      @ignore_tag_error = enabled
    end

    # runs all methods with the specified tags
    # @param [Symbol] tags
    # @param [Object] args arguments
    def run_tag(*tags, **args, &block)
      t = self.tags
      tags.each do |e|
        next if t.include?(e)
        raise Yuuki::Error, "tag `#{e}` is not associated" unless @ignore_tag_error

        warn "Yuuki Warning: tag `#{e}` is not associated"
      end
      run_select(proc {|_method, meta| meta[:tags]&.intersect?(tags)}, **args, &block)
    end

    # runs the specific method
    # @param [Class, nil] klass
    # @param [Symbol, nil] method_sig method name
    # @param [Object] args arguments
    def run_method(klass, method_sig, **args, &block)
      select_proc = proc do |method, _meta|
        flag_klass = klass ? method.receiver.instance_of?(klass) : true
        flag_method = method_sig ? method.name == method_sig : true
        flag_klass && flag_method
      end
      run_select(select_proc, **args, &block)
    end

    # joins all runnning threads
    def join
      @threads.each(&:join)
      @threads.select!(&:alive?)
    end

    # returns whether any thread is alive
    # @return [Boolean]
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

    def run_method_internal(method, args, &block)
      params = method.parameters
      return method[] if params.empty?

      yoshinon = Yoshinon.lock if @use_yoshinon
      params_array = []
      params_hash = {}
      params_block = nil
      nonspecified_last_opt = nil
      params.each do |type, name|
        case type
        when :req
          unless args.key?(name)
            raise Yuuki::Error, "A required argument '#{name}' was not found on running #{method.owner}::#{method.name}"
          end

          params_array << args[name]
        when :opt
          # if parameters do not contain the :opt argument, treat it as not specified
          next nonspecified_last_opt = name unless args.key?(name)

          if nonspecified_last_opt
            # if there already exist non-specified :opt arguments, no more specified :opt argument is allowed
            raise Yuuki::Error, "A required argument '#{nonspecified_last_opt}' was not found"\
                    " on running #{method.owner}::#{method.name}"" with optional argument '#{name}'"
          end
          params_array << args[name]
        when :rest
          next unless args.key?(name)

          if nonspecified_last_opt
            # if there already exist non-specified :opt arguments, the :rest argument cannot be handled
            raise Yuuki::Error, "A required argument '#{nonspecified_last_opt}' not found"\
                    " on running #{method.owner}::#{method.name}"" with rest argument '#{name}'"
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
          params_block = args[name]
        end
      end
      params_block = block unless params.any? {|type, _| type == :block}
      params_hash.empty? ? method[*params_array, &params_block] : method[*params_array, **params_hash, &params_block]
    ensure
      yoshinon&.unlock
    end
  end
end
