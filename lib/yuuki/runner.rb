# frozen_string_literal: true

module Yuuki
  class Runner
    attr_reader :yuuki

    # Decorator-style DSL (`on` / `priority` / `thread` / `periodic` / `first_run`)
    # pushes entries here; the next instance-method definition consumes them
    # (see method_added). Both this and yuuki_methods live in per-class ivars.
    def self.accumulated_decorators
      @accumulated_decorators ||= []
    end

    def self.yuuki_methods
      @yuuki_methods ||= {}
    end

    # yuuki_methods is a per-class ivar, so copy it on inheritance to make
    # runner methods defined in a superclass visible from the subclass.
    # NOTE: methods added to the superclass after the subclass is defined are
    # not reflected.
    def self.inherited(subclass)
      subclass.instance_variable_set(:@yuuki_methods, yuuki_methods.dup)
      super
    end

    def self.on(tag)
      accumulated_decorators << [:tag, tag]
    end

    def self.priority(priority = 0)
      accumulated_decorators << [:priority, priority]
    end

    def self.thread(enabled: true)
      accumulated_decorators << [:thread, enabled]
    end

    def self.periodic(interval)
      accumulated_decorators << [:periodic, interval]
    end

    def self.first_run(enabled: true)
      accumulated_decorators << [:first_run, enabled]
    end

    # Registers the method as a runner method when decorators are pending or the
    # name is `on_<tag>` (which implies the tag <tag>). Note this hook fires for
    # ANY instance-method definition, including attr_* and private helpers, so
    # pending decorators are consumed by whatever method comes next.
    def self.method_added(method_name)
      return if accumulated_decorators.empty? && !method_name.start_with?('on_')

      options = {}
      options[:tags] = [method_name[3..].to_sym] if method_name.start_with?('on_')

      accumulated_decorators.each do |tag, elem|
        if tag == :tag
          options[:tags] ||= []
          options[:tags] << elem
        else
          options[tag] = elem
        end
      end
      accumulated_decorators.clear

      yuuki_methods[method_name] = options

      super
    end

    def self.singleton_method_added(_method_name)
      accumulated_decorators.clear
      super
    end
  end
end
