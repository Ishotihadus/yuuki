require 'yuuki/runner'

module Yuuki
    class Caller
        Runner = Struct.new(:method, :tags, :exclude, :threading, :priority)

        def self.require_dir(dir, recursive = false)
            Dir.glob(recursive ? "#{require_dir}/**/*.rb" : "#{require_dir}/*.rb"){|file| require file}
        end

        def initialize(*klass)
            @runners = []
            @threads = []
            add(*klass)
        end

        def add(*klass)
            klass.each do |klass|
                instance = klass.new
                instance.instance_variable_set(:@caller, self)
                info = klass.instance_variable_get(:@runner_info) || {}
                methods = klass.public_instance_methods(false)
                methods |= klass.instance_variable_get(:@runner_adds) || []
                methods -= klass.instance_variable_get(:@runner_excepts) || []
                @runners += methods.map do |method|
                    tags = info.dig(method, :tags) || []
                    exclude = !!info.dig(method, :exclude)
                    threading = !!info.dig(method, :threading)
                    priority = info.dig(method, :priority) || 0
                    Runner.new(instance.method(method), tags, exclude, threading, priority)
                end
            end
            @runners.sort_by!{|e| -e.priority}
        end

        def run(**args)
            run_internal(@runners.reject(&:exclude), args)
        end

        def run_all(**args)
            run_internal(@runners, args)
        end

        def run_class(*klass, **args)
            run_internal(@runners.select{|e| !e.exclude && klass.any?{|k| e.method.receiver.instance_of?(k)}}, args)
        end

        def run_class_all(*klass, **args)
            run_internal(@runners.select{|e| klass.any?{|k| e.method.receiver.instance_of?(k)}}, args)
        end

        def run_tag(*tags, **args)
            run_internal(@runners.select{|e| tags.any?{|t| e.tags.any?(t)}}, args)
        end

        def run_select(**args)
            run_internal(@runners.select{|e| yield(e)}, args)
        end

        def run_method(klass, method, **args)
            runners = klass ? @runners.select{|e| e.method.receiver.class == klass} : @runners
            runners.select!{|e| e.method.name == method} if method
            run_internal(runners, args)
        end

        def join
            @threads.each(&:join)
        end

        def alive?
            @threads.any?(&:alive?)
        end
        alias running? alive?

        private

        def run_internal(runners, args)
            runners.each do |runner|
                if runner.threading
                    @threads << Thread.new(runner.method, args) do |method, args|
                        run_method_internal(method, args)
                    end
                else
                    run_method_internal(runner.method, args)
                end
            end
            @threads.select!(&:alive?)
        end

        def run_method_internal(method, args)
            params = method.parameters
            return method[] if params.size == 0
            params_array = []
            params_hash = {}
            params_block = nil
            nonspecified_last_opt = nil
            params.each do |type, name|
                case type
                when :req
                    raise Yuuki::Error.new("A required argument '#{name}' was not found on running #{method.owner}::#{method.name}") unless args.key?(name)
                    params_array << args[name]
                when :opt
                    next nonspecified_last_opt = name unless args.key?(name)
                    raise Yuuki::Error.new("A required argument '#{nonspecified_last_opt}' was not found"\
                        " on running #{method.owner}::#{method.name}"" with optional argument '#{name}'") if nonspecified_last_opt
                    params_array << args[name]
                when :rest
                    next unless args.key?(name)
                    raise Yuuki::Error.new("A required argument '#{nonspecified_last_opt}' not found"\
                        " on running #{method.owner}::#{method.name}"" with rest argument '#{name}'") if nonspecified_last_opt
                    if args[name].respond_to?(:to_ary)
                        params_array += args[name]
                    else
                        params_array << args[name]
                    end
                when :keyreq
                    raise Yuuki::Error.new("A required key argument '#{name}' was not found on running #{method.owner}::#{method.name}") unless args.key?(name)
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
            params_hash.empty? ? method[*params_array, &params_block] : method[*params_array, **params_hash, &params_block]
        end
    end
end
