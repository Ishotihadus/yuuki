# Yuuki

A caller / runner framework for Ruby.

Yuuki lets you tag methods of a class and invoke them by tag. Arguments are delivered to each method by parameter name, and methods can be run in threads, ordered by priority, or executed periodically.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'yuuki'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install yuuki

## Usage

### Basics

Define a runner class that inherits `Yuuki::Runner`. A method named `on_<tag>` is automatically registered with the tag `<tag>`. Any other method can be registered with the `on` decorator, which applies to the next method definition.

```ruby
require 'yuuki'

class Greeter < Yuuki::Runner
  # registered with the tag :greet (taken from the method name)
  def on_greet
    puts 'hello!'
  end

  # registered with the tags :greet and :farewell
  on :greet
  on :farewell
  def say_goodbye
    puts 'goodbye!'
  end
end

yuuki = Yuuki::Caller.new(Greeter)
yuuki.run(:greet)
# hello!
# goodbye!

yuuki.run(:farewell)
# goodbye!
```

`Yuuki::Caller.new` (and `#add`) accepts runner classes and runner instances. A class is instantiated automatically. Inside a runner method, `yuuki` returns the caller the instance belongs to.

### Passing arguments

Keyword arguments given to `run` are delivered to each method by parameter name — no matter whether the parameter is positional or keyword. Extra arguments are simply ignored, and a missing required parameter raises `Yuuki::Error`. A block given to `run` is forwarded as the block of each method.

```ruby
class Worker < Yuuki::Runner
  def on_process(name, size: 1)
    puts "processing #{name} (size: #{size})"
  end
end

yuuki = Yuuki::Caller.new(Worker)
yuuki.run(:process, name: 'job', size: 3, unused: 42)
# processing job (size: 3)
```

### Decorators

Decorators are class methods that annotate the **next** method definition.

| Decorator | Effect |
| --- | --- |
| `on :tag` | Adds a tag. Can be specified multiple times. |
| `priority n` | Runs methods with higher priority first (default 0). Also used as `Thread#priority` for threaded methods. |
| `thread` | Runs the method in a new thread. |
| `periodic interval` | Runs the method every `interval` seconds (`Yuuki::PeriodicCaller` only). |
| `first_run` | Runs the method once on startup (`Yuuki::PeriodicCaller` only). |

### Threading

Methods marked with `thread` run in their own thread; `run` returns without waiting for them.

```ruby
class Background < Yuuki::Runner
  on :heavy
  thread
  def heavy_task
    sleep 1
    puts 'done'
  end
end

yuuki = Yuuki::Caller.new(Background)
yuuki.run(:heavy) # returns immediately
yuuki.running?    # => true
yuuki.join        # waits for all running threads
```

### Periodic execution

`Yuuki::PeriodicCaller` runs `periodic` methods repeatedly and `first_run` methods once on startup. It is not required by default:

```ruby
require 'yuuki/periodic_caller'

class Watcher < Yuuki::Runner
  first_run
  def setup
    puts 'starting'
  end

  periodic 60
  def check
    puts 'checking...'
  end

  periodic 86_400
  def daily
    puts 'a new day has come'
  end
end

yuuki = Yuuki::PeriodicCaller.new(Watcher)
yuuki.on_error { |error| warn error.message }
yuuki.run # blocks forever
```

Intervals are aligned to wall-clock boundaries in local time: `periodic 60` fires at the top of every minute, and `periodic 86_400` fires at local midnight (pass a GMT offset as the first argument of `run` to change the time zone). Intervals shorter than 1 second are not supported.

An exception raised by a (non-threaded) runner method is passed to the `on_error` callback and the loop keeps running. Without `on_error`, the exception stops `run`.

### Loading runner files

`Yuuki::Caller.require_dir` requires all `*.rb` files in a directory:

```ruby
Yuuki::Caller.require_dir('runners')
Yuuki::Caller.require_dir('runners', recursive: true)
```

### Graceful shutdown with Yoshinon

By default, each method invocation is wrapped in a [Yoshinon](https://github.com/Ishotihadus/yoshinon) lock so that a trapped signal waits for running methods to finish. Pass `use_yoshinon: false` to `Yuuki::Caller.new` to disable this.

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/ishotihadus/yuuki](https://github.com/ishotihadus/yuuki).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
