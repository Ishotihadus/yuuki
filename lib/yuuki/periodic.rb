# frozen_string_literal: true

require 'yuuki/caller'
require 'yuuki/runner'

module Yuuki
  module Runner
    # set interval to the method
    def periodic(method, interval)
      @yuuki_methods ||= {}
      @yuuki_methods[method] ||= {}
      @yuuki_methods[method][:periodic] = interval
    end

    # set whether the method run at the first time
    def first_run(method, enabled: true)
      @yuuki_methods ||= {}
      @yuuki_methods[method] ||= {}
      @yuuki_methods[method][:first_run] = enabled
    end
  end
end

module Yuuki
  class PeriodicCaller < Caller
    attr_reader :first_run, :current_time

    def initialize(*instances)
      super
      @first_run = true
    end

    def on_error(&block)
      @on_error = block
    end

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
