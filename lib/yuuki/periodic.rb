# frozen_string_literal: true

require 'yuuki/caller'
require 'yuuki/runner'

module Yuuki
  module Runner
    # sets interval to the method
    # @param [Symbol] methods method names
    # @param [Integer] interval
    def periodic(*methods, interval)
      @yuuki_methods ||= {}
      methods.each do |method|
        @yuuki_methods[method] ||= {}
        @yuuki_methods[method][:periodic] = interval
      end
    end

    # sets whether the method run at the first time
    # @param [Symbol] methods method names
    # @param [Boolean] enabled
    def first_run(*methods, enabled: true)
      @yuuki_methods ||= {}
      methods.each do |method|
        @yuuki_methods[method] ||= {}
        @yuuki_methods[method][:first_run] = enabled
      end
    end
  end
end

module Yuuki
  # @attr_reader [Boolean] first_run
  # @attr_reader [Float] current_time
  class PeriodicCaller < Caller
    attr_reader :first_run, :current_time

    def initialize(*instances)
      super
      @first_run = true
    end

    # sets error callback
    # @yield [error]
    # @yieldparam [Exception] error
    def on_error(&block)
      @on_error = block
    end

    # runs the periodic caller
    # @param [Numeric] gmtoff GMT Offset
    # @param [Object] args arguments
    def run(gmtoff = Time.now.gmtoff, **args, &block)
      last_time = nil
      loop do
        @current_time = Time.now.to_f
        begin
          select_proc = proc do |_method, meta|
            next true if @first_run && meta[:first_run]
            next false unless meta[:periodic]
            next false unless last_time
            c = @current_time + gmtoff
            l = last_time + gmtoff
            next true if (l.div(meta[:periodic]) + 1) * meta[:periodic] <= c
          end
          run_select(select_proc, **args, &block)
        rescue
          @on_error ? @on_error[$!] : raise
        end
        @first_run = false

        last_time = @current_time
        ((@current_time + 1).floor - Time.now.to_f).tap{|e| sleep e if e > 0}
      end
    end
  end
end
