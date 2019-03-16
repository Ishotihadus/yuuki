require 'yuuki/error'

module Yuuki
    class RunnerBase
        class << self
            private

            def add(*methods)
                @runner_adds ||= []
                @runner_adds |= methods
            end

            def delete(*methods)
                @runner_excepts ||= []
                @runner_excepts |= methods
            end

            def tag(method, *tags)
                @runner_info ||= {}
                @runner_info[method] ||= {}
                @runner_info[method][:tags] ||= []
                @runner_info[method][:tags] |= tags
            end

            def exclude(*methods)
                @runner_info ||= {}
                methods.each do |method|
                    @runner_info[method] ||= {}
                    @runner_info[method][:exclude] = true
                end
            end

            def threading(*methods)
                @runner_info ||= {}
                methods.each do |method|
                    @runner_info[method] ||= {}
                    @runner_info[method][:threading] = true
                end
            end

            def priority(method, priority)
                @runner_info ||= {}
                @runner_info[method] ||= {}
                @runner_info[method][:priority] = priority
            end
        end
    end
end
