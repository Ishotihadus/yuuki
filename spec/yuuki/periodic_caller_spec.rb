# frozen_string_literal: true

require 'yuuki/periodic_caller'

RSpec.describe Yuuki::PeriodicCaller do
  def run_in_thread(periodic_caller, **args)
    thread = Thread.new { periodic_caller.run(**args) }
    yield thread
  ensure
    thread.kill
    thread.join
  end

  it 'runs first_run methods immediately and only once' do
    klass = Class.new(Yuuki::Runner) do
      first_run
      def boot(collector)
        collector << :boot
      end
    end
    collector = []
    periodic_caller = described_class.new(klass, use_yoshinon: false)
    run_in_thread(periodic_caller, collector: collector) do
      sleep 0.2
      expect(collector).to eq([:boot])
    end
  end

  it 'does not run periodic-only methods on the first iteration' do
    klass = Class.new(Yuuki::Runner) do
      periodic 3600
      def tick(collector)
        collector << :tick
      end
    end
    collector = []
    periodic_caller = described_class.new(klass, use_yoshinon: false)
    run_in_thread(periodic_caller, collector: collector) do
      sleep 0.2
      expect(collector).to be_empty
    end
  end

  it 'runs periodic methods at each interval boundary' do
    klass = Class.new(Yuuki::Runner) do
      periodic 1
      def tick(collector)
        collector << :tick
      end
    end
    collector = []
    periodic_caller = described_class.new(klass, use_yoshinon: false)
    run_in_thread(periodic_caller, collector: collector) do
      sleep 2.3
      expect(collector.size).to be_between(2, 3)
    end
  end

  describe '#on_error' do
    let(:klass) do
      Class.new(Yuuki::Runner) do
        first_run
        def boom
          raise 'boom'
        end
      end
    end

    it 'passes the raised error to the callback and keeps running' do
      errors = []
      periodic_caller = described_class.new(klass, use_yoshinon: false)
      periodic_caller.on_error { |error| errors << error }
      run_in_thread(periodic_caller) do |thread|
        sleep 0.2
        expect(errors.size).to eq(1)
        expect(errors.first).to be_a(RuntimeError)
        expect(errors.first.message).to eq('boom')
        expect(thread).to be_alive
      end
    end

    it 'raises when no callback is set' do
      periodic_caller = described_class.new(klass, use_yoshinon: false)
      expect { periodic_caller.run }.to raise_error(RuntimeError, 'boom')
    end
  end
end
