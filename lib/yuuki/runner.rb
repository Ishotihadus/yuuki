# frozen_string_literal: true

module Yuuki
  module Runner
    def self.extended(base)
      base.define_method(:yuuki) do
        @yuuki
      end
    end

    # adds methods to yuuki
    # @param [Array<Symbol>] methods method names
    def add(*methods)
      @yuuki_methods ||= {}
      methods.each do |method|
        @yuuki_methods[method] ||= {}
        @yuuki_methods[method][:enabled] = true
      end
    end

    # deletes methods from yuuki
    # @param [Array<Symbol>] methods method names
    def delete(*methods)
      @yuuki_methods ||= {}
      methods.each do |method|
        @yuuki_methods[method] ||= {}
        @yuuki_methods[method][:enabled] = false
      end
    end

    # adds tags to the method
    # @param [Symbol] method method name
    # @param [Array<Symbol>] tags tag names
    def tag(method, *tags)
      @yuuki_methods ||= {}
      @yuuki_methods[method] ||= {}
      @yuuki_methods[method][:tags] ||= Set.new
      @yuuki_methods[method][:tags].merge(tags)
    end

    # enables threading for the methods
    # @param [Array<Symbol>] methods method names
    # @param [Boolean] enabled
    def thread(*methods, enabled: true)
      @yuuki_methods ||= {}
      methods.each do |method|
        @yuuki_methods[method] ||= {}
        @yuuki_methods[method][:thread] = enabled
      end
    end

    # sets priority to the method
    # @param [Array<Symbol>] methods method names
    # @param [Numeric] value
    def priority(*methods, value)
      @yuuki_methods ||= {}
      methods.each do |method|
        @yuuki_methods[method] ||= {}
        @yuuki_methods[method][:priority] = value
      end
    end
  end
end
