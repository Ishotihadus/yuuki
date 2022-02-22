# frozen_string_literal: true

require 'set'

module Yuuki
  module Runner
    # add method
    def add(*methods)
      @yuuki_methods ||= {}
      methods.each do |method|
        @yuuki_methods[method] ||= {}
        @yuuki_methods[method][:enabled] = true
      end
    end

    # delete method
    def delete(*methods)
      @yuuki_methods ||= {}
      methods.each do |method|
        @yuuki_methods[method] ||= {}
        @yuuki_methods[method][:enabled] = false
      end
    end

    # add tags to the method
    def tag(method, *tags)
      @yuuki_methods ||= {}
      @yuuki_methods[method] ||= {}
      @yuuki_methods[method][:tags] ||= Set.new
      @yuuki_methods[method][:tags].merge(tags)
    end

    # enable threading to the method
    def thread(*methods, enabled: true)
      @yuuki_methods ||= {}
      methods.each do |method|
        @yuuki_methods[method] ||= {}
        @yuuki_methods[method][:thread] = enabled
      end
    end

    # set priority to the method
    def priority(*methods, priority)
      @yuuki_methods ||= {}
      methods.each do |method|
        @yuuki_methods[method] ||= {}
        @yuuki_methods[method][:priority] = priority
      end
    end
  end
end
