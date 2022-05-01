# frozen_string_literal: true

require_relative 'test_helper'

class TestClass
  extend Yuuki::Runner

  attr_reader :test

  def initialize
    @test = []
  end

  add :a
  def a
    @test << :a
  end

  add :b
  tag :b, :tag_b
  def b
    @test << :b
  end

  def c
    @test << :c
  end

  add :d
  delete :d
  def d
    @test << :d
  end

  add :e
  priority :e, 5
  def e
    @test << :e
  end

  add :f
  thread :f
  def f
    sleep 1
    @test << :f
  end

  add :g
  tag :g, :tag_g
  def g
    @test << :g
    @yuuki.run_tag(:tag_b)
  end
end

class UsaminTest < Minitest::Test
  def setup
    @instance = TestClass.new
    @yuuki = Yuuki::Caller.new(@instance)
  end

  def test_that_it_has_a_version_number
    refute_nil ::Yuuki::VERSION
  end

  def test_success
    @yuuki.run
    assert_equal(@instance.test, %i[e a b g b])
  end

  def test_thread
    @yuuki.run
    assert_equal(@yuuki.alive?, true)
    @yuuki.join
    assert_equal(@instance.test, %i[e a b g b f])
    assert_equal(@yuuki.alive?, false)
  end

  def test_tag_b
    @yuuki.run_tag(:tag_b)
    assert_equal(@instance.test, %i[b])
  end

  def test_tag_g
    @yuuki.run_tag(:tag_g)
    assert_equal(@instance.test, %i[g b])
  end

  def test_tags
    assert_equal(@yuuki.tags, Set[:tag_b, :tag_g])
  end
end
