$LOAD_PATH.unshift File.expand_path('../../test', __FILE__)
require 'test_helper'

class LikableTest < MiniTest::Unit::TestCase
  def setup
    @user = Factory(:user)
    @friend = Factory(:user)
    @movie = Factory(:movie)
  end

  def test_liked_by_returns_relevant_users
    assert_empty @movie.liked_by
    @user.like(@movie)
    assert_includes @movie.liked_by, @user
    refute_includes @movie.liked_by, @friend
    @friend.like(@movie)
    assert_includes @movie.liked_by, @friend
  end

  def test_liked_by_count_returns_an_accurate_count
    assert_empty @movie.liked_by
    @user.like(@movie)
    assert_equal @movie.liked_by_count, 1
    @friend.like(@movie)
    assert_equal @movie.liked_by_count, 2
  end

  def test_weighted_liked_by_returns_relevant_users
    assert_empty @movie.weighted_liked_by
    @user.weighted_like(@movie, 2.0)
    assert_includes @movie.weighted_liked_by, @user
    refute_includes @movie.weighted_liked_by, @friend
    @friend.weighted_like(@movie, 3.0)
    assert_includes @movie.weighted_liked_by, @friend
  end

  def test_weighted_liked_by_count_returns_an_accurate_count_and_weight
    assert_empty @movie.weighted_liked_by
    @user.weighted_like(@movie, 2.0)
    assert_equal @movie.weighted_liked_by_count, 1
    @friend.weighted_like(@movie, 3.0)
    assert_equal @movie.weighted_liked_by_count, 2
  end

  def teardown
    Recommendable.redis.flushdb
  end
end
