# frozen_string_literal: true

RSpec.describe Yuuki::Caller do
  describe '.require_dir' do
    it 'requires rb files in the directory (non-recursive)' do
      $yuuki_spec_loaded = []
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.rb'), '$yuuki_spec_loaded << :a')
        FileUtils.mkdir(File.join(dir, 'sub'))
        File.write(File.join(dir, 'sub', 'b.rb'), '$yuuki_spec_loaded << :b')
        described_class.require_dir(dir)
      end
      expect($yuuki_spec_loaded).to eq([:a])
    end

    it 'requires rb files recursively with recursive: true' do
      $yuuki_spec_loaded = []
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.rb'), '$yuuki_spec_loaded << :a')
        FileUtils.mkdir(File.join(dir, 'sub'))
        File.write(File.join(dir, 'sub', 'b.rb'), '$yuuki_spec_loaded << :b')
        described_class.require_dir(dir, recursive: true)
      end
      expect($yuuki_spec_loaded).to contain_exactly(:a, :b)
    end
  end

  describe '#add' do
    let(:runner_class) do
      Class.new(Yuuki::Runner) do
        def on_probe(collector)
          collector << self
        end
      end
    end

    it 'accepts a direct subclass of Yuuki::Runner' do
      expect { described_class.new(runner_class, use_yoshinon: false) }.not_to raise_error
    end

    it 'accepts a grandchild class of Yuuki::Runner' do
      grandchild = Class.new(runner_class)
      collector = []
      caller = described_class.new(grandchild, use_yoshinon: false)
      caller.run(:probe, collector: collector)
      expect(collector.first).to be_a(grandchild)
    end

    it 'accepts a runner instance' do
      instance = runner_class.new
      collector = []
      caller = described_class.new(instance, use_yoshinon: false)
      caller.run(:probe, collector: collector)
      expect(collector).to eq([instance])
      expect(instance.yuuki).to be(caller)
    end

    it 'does not run the same instance twice when added twice' do
      instance = runner_class.new
      caller = described_class.new(instance, use_yoshinon: false)
      caller.add(instance)
      collector = []
      caller.run(:probe, collector: collector)
      expect(collector.size).to eq(1)
    end

    it 'rejects a class that does not inherit Yuuki::Runner' do
      expect { described_class.new(String) }.to raise_error(Yuuki::Error)
    end

    it 'rejects an instance that is not a Yuuki::Runner' do
      expect { described_class.new('runner') }.to raise_error(Yuuki::Error)
    end

    it 'sets @yuuki before #initialize runs' do
      klass = Class.new(Yuuki::Runner) do
        attr_reader :yuuki_in_initialize

        def initialize
          @yuuki_in_initialize = yuuki
        end

        def on_probe(collector)
          collector << self
        end
      end
      caller = described_class.new(klass, use_yoshinon: false)
      collector = []
      caller.run(:probe, collector: collector)
      expect(collector.first.yuuki_in_initialize).to be(caller)
    end
  end

  describe '#methods' do
    it 'returns [Method, meta] pairs sorted by priority (highest first)' do
      klass = Class.new(Yuuki::Runner) do
        on :a
        priority 1
        def low; end

        on :a
        priority 10
        def high; end

        on :a
        def default; end
      end
      caller = described_class.new(klass, use_yoshinon: false)
      expect(caller.methods.map { |method, _meta| method.name }).to eq(%i[high low default])
    end
  end

  describe '#run' do
    let(:runner_class) do
      Class.new(Yuuki::Runner) do
        on :foo
        def foo_method(collector)
          collector << :foo
        end

        on :bar
        def bar_method(collector)
          collector << :bar
        end

        on :foo
        on :bar
        def both_method(collector)
          collector << :both
        end
      end
    end
    let(:caller) { described_class.new(runner_class, use_yoshinon: false) }
    let(:collector) { [] }

    it 'runs only the methods matching the given tag' do
      caller.run(:foo, collector: collector)
      expect(collector).to contain_exactly(:foo, :both)
    end

    it 'runs methods matching any of multiple tags' do
      caller.run(:foo, :bar, collector: collector)
      expect(collector).to contain_exactly(:foo, :bar, :both)
    end

    it 'runs nothing when no tags are given' do
      caller.run(collector: collector)
      expect(collector).to be_empty
    end

    it 'works with the default use_yoshinon: true' do
      caller = described_class.new(runner_class)
      caller.run(:foo, collector: collector)
      expect(collector).to contain_exactly(:foo, :both)
    end
  end

  describe 'argument mapping' do
    let(:runner_class) do
      Class.new(Yuuki::Runner) do
        on :req
        def m_req(collector, a)
          collector << a
        end

        on :opt
        def m_opt(collector, a = :default_a, b = :default_b)
          collector << [a, b]
        end

        on :rest
        def m_rest(collector, *rest)
          collector << rest
        end

        on :optrest
        def m_optrest(collector, a = :default_a, *rest)
          collector << [a, rest]
        end

        on :keyreq
        def m_keyreq(collector, k:)
          collector << k
        end

        on :key
        def m_key(collector, k: :default_k)
          collector << k
        end

        on :keyrest
        def m_keyrest(collector, **kw)
          collector << kw
        end

        on :block
        def m_block(collector, &blk)
          collector << blk&.call
        end

        on :yield
        def m_yield
          yield
        end
      end
    end
    let(:caller) { described_class.new(runner_class, use_yoshinon: false) }
    let(:collector) { [] }

    context 'with required positional arguments' do
      it 'passes the argument by name' do
        caller.run(:req, collector: collector, a: 1)
        expect(collector).to eq([1])
      end

      it 'raises when a required argument is missing' do
        expect { caller.run(:req, collector: collector) }.to raise_error(Yuuki::Error, /'a'/)
      end
    end

    context 'with optional positional arguments' do
      it 'passes all specified arguments' do
        caller.run(:opt, collector: collector, a: 1, b: 2)
        expect(collector).to eq([[1, 2]])
      end

      it 'uses the default for trailing unspecified arguments' do
        caller.run(:opt, collector: collector, a: 1)
        expect(collector).to eq([[1, :default_b]])
      end

      it 'raises when a later optional argument is specified but an earlier one is not' do
        expect { caller.run(:opt, collector: collector, b: 2) }.to raise_error(Yuuki::Error, /'a'/)
      end
    end

    context 'with rest arguments' do
      it 'splats an array value' do
        caller.run(:rest, collector: collector, rest: [1, 2])
        expect(collector).to eq([[1, 2]])
      end

      it 'passes a non-array value as a single element' do
        caller.run(:rest, collector: collector, rest: 3)
        expect(collector).to eq([[3]])
      end

      it 'passes nothing when unspecified' do
        caller.run(:rest, collector: collector)
        expect(collector).to eq([[]])
      end

      it 'raises when rest is specified but an earlier optional argument is not' do
        expect { caller.run(:optrest, collector: collector, rest: [1]) }.to raise_error(Yuuki::Error, /'a'/)
      end
    end

    context 'with keyword arguments' do
      it 'passes a required keyword argument' do
        caller.run(:keyreq, collector: collector, k: 1)
        expect(collector).to eq([1])
      end

      it 'raises when a required keyword argument is missing' do
        expect { caller.run(:keyreq, collector: collector) }.to raise_error(Yuuki::Error, /'k'/)
      end

      it 'passes an optional keyword argument' do
        caller.run(:key, collector: collector, k: 1)
        expect(collector).to eq([1])
      end

      it 'uses the default for an unspecified optional keyword argument' do
        caller.run(:key, collector: collector)
        expect(collector).to eq([:default_k])
      end

      it 'merges a hash value into keyrest' do
        caller.run(:keyrest, collector: collector, kw: { x: 1, y: 2 })
        expect(collector).to eq([{ x: 1, y: 2 }])
      end

      it 'passes a non-hash keyrest value under its own name' do
        caller.run(:keyrest, collector: collector, kw: 5)
        expect(collector).to eq([{ kw: 5 }])
      end

      it 'passes an empty hash when keyrest is unspecified' do
        caller.run(:keyrest, collector: collector)
        expect(collector).to eq([{}])
      end
    end

    context 'with blocks' do
      it 'passes a block specified via args' do
        caller.run(:block, collector: collector, blk: proc { :from_args })
        expect(collector).to eq([:from_args])
      end

      it 'falls back to the block passed to run' do
        caller.run(:block, collector: collector) { :given }
        expect(collector).to eq([:given])
      end

      it 'respects an explicit nil block in args over the given block' do
        caller.run(:block, collector: collector, blk: nil) { :given }
        expect(collector).to eq([nil])
      end

      it 'passes the block to a method without parameters' do
        result = nil
        caller.run(:yield) { result = :yielded }
        expect(result).to eq(:yielded)
      end
    end
  end

  describe 'threading' do
    let(:runner_class) do
      Class.new(Yuuki::Runner) do
        on :bg
        thread
        def slow(queue)
          sleep 0.2
          queue << :done
        end
      end
    end
    let(:caller) { described_class.new(runner_class, use_yoshinon: false) }

    it 'runs the method in a thread and joins it' do
      queue = Queue.new
      caller.run(:bg, queue: queue)
      expect(caller.alive?).to be true
      expect(caller.running?).to be true
      caller.join
      expect(queue.size).to eq(1)
      expect(caller.alive?).to be false
    end
  end
end
