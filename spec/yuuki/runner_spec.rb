# frozen_string_literal: true

RSpec.describe Yuuki::Runner do
  describe '.method_added' do
    it 'registers a method with pending decorators' do
      klass = Class.new(described_class) do
        on :foo
        priority 5
        thread
        periodic 10
        first_run
        def run_me; end
      end
      expect(klass.yuuki_methods[:run_me]).to eq(
        tags: [:foo], priority: 5, thread: true, periodic: 10, first_run: true
      )
    end

    it 'does not register an undecorated method' do
      klass = Class.new(described_class) do
        def plain; end
      end
      expect(klass.yuuki_methods).not_to have_key(:plain)
    end

    it 'auto-registers on_-prefixed methods with the tag taken from the name' do
      klass = Class.new(described_class) do
        def on_foo; end
      end
      expect(klass.yuuki_methods[:on_foo]).to eq(tags: [:foo])
    end

    it 'appends decorator tags to the implicit on_ tag' do
      klass = Class.new(described_class) do
        on :bar
        def on_foo; end
      end
      expect(klass.yuuki_methods[:on_foo][:tags]).to contain_exactly(:foo, :bar)
    end

    it 'consumes decorators so they do not leak to the next method' do
      klass = Class.new(described_class) do
        on :foo
        def first; end
        def second; end
      end
      expect(klass.yuuki_methods).to have_key(:first)
      expect(klass.yuuki_methods).not_to have_key(:second)
    end
  end

  describe '.singleton_method_added' do
    it 'discards pending decorators when a class method is defined in between' do
      klass = Class.new(described_class) do
        on :foo
        def self.helper; end

        def target; end
      end
      expect(klass.yuuki_methods).not_to have_key(:target)
    end
  end

  describe '.inherited' do
    it 'copies registrations to the subclass' do
      base = Class.new(described_class) do
        on :foo
        def base_method; end
      end
      child = Class.new(base)
      expect(child.yuuki_methods[:base_method]).to eq(tags: [:foo])
    end

    it 'does not propagate subclass registrations back to the superclass' do
      base = Class.new(described_class)
      Class.new(base) do
        on :foo
        def child_method; end
      end
      expect(base.yuuki_methods).not_to have_key(:child_method)
    end

    it 'lets the subclass override an inherited registration' do
      base = Class.new(described_class) do
        on :foo
        def run_me; end
      end
      child = Class.new(base) do
        on :bar
        def run_me; end
      end
      expect(child.yuuki_methods[:run_me]).to eq(tags: [:bar])
      expect(base.yuuki_methods[:run_me]).to eq(tags: [:foo])
    end
  end
end
