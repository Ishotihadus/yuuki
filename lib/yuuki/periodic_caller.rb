# frozen_string_literal: true

require 'yoshinon'
require 'yuuki/caller'
require 'yuuki/runner'

module Yuuki
  class PeriodicCaller < Caller
    attr_reader :first_run, :current_time

    def initialize(*instances, use_yoshinon: true)
      super
      @first_run = true
    end

    def on_error(&block)
      @on_error = block
    end

    def start(gmtoff = Time.now.gmtoff, **args, &block)
      last_time = nil
      loop do
        @current_time = Time.now.to_f
        begin
          selector = proc do |_method, meta|
            next true if @first_run && meta[:first_run]
            next false unless meta[:periodic]
            next false unless last_time

            # gmtoff shifts epoch seconds into local time so that intervals
            # align with local clock boundaries (e.g. 86400 fires at local midnight).
            # Fires when a multiple of the interval lies in (last_time, current_time].
            c = @current_time + gmtoff
            l = last_time + gmtoff
            (l.div(meta[:periodic]) + 1) * meta[:periodic] <= c
          end
          run_select(selector, **args, &block)
        rescue StandardError
          @on_error ? @on_error[$!] : raise
        end
        @first_run = false

        last_time = @current_time
        # wake at the next wall-clock second; the boundary check above makes
        # ticks drift-free, but intervals below 1 second cannot be honored
        sleep_duration = (@current_time + 1).floor - Time.now.to_f
        sleep(sleep_duration) if sleep_duration > 0
      end
    end
  end
end
