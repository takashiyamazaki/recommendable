$LOAD_PATH.unshift File.expand_path('../../test', __FILE__)
require 'test_helper'

class CalculationsTest < MiniTest::Unit::TestCase
  def setup
    @user = Factory(:user)
    5.times  { |x| instance_variable_set(:"@user#{x+1}",  Factory(:user))  }
    5.times { |x| instance_variable_set(:"@movie#{x+1}", Factory(:movie)) }
    5.upto(9) { |x| instance_variable_set(:"@movie#{x+1}", Factory(:documentary)) }
    10.times { |x| instance_variable_set(:"@book#{x+1}",  Factory(:book))  }

    [@movie1, @movie2, @movie3, @book4, @book5, @book6].each { |obj| @user.like(obj) }
    [@book1, @book2, @book3, @movie4, @movie5, @movie6].each { |obj| @user.dislike(obj) }

    # @user.similarity_with(@user1) should ==  1.0
    [@movie1, @movie2, @movie3, @book4, @book5, @book6, @book7, @book8, @movie9, @movie10].each { |obj| @user1.like(obj) }
    [@book1, @book2, @book3, @movie4, @movie5, @movie6, @movie7, @movie8, @book9, @book10].each { |obj| @user1.dislike(obj) }

    # @user.similarity_with(@user2) should ==  0.25
    [@movie1, @movie2, @movie3, @book4, @book5, @book6].each { |obj| @user2.like(obj) }
    [@book1, @book2, @book3].each { |obj| @user2.like(obj) }

    # @user.similarity_with(@user3) should ==  0.0
    [@movie1, @movie2, @movie3].each { |obj| @user3.like(obj) }
    [@book1, @book2, @book3].each { |obj| @user3.like(obj) }

    # @user.similarity_with(@user4) should == -0.25
    [@movie1, @movie2, @movie3].each { |obj| @user4.like(obj) }
    [@book1, @book2, @book3, @movie4, @movie5, @movie6].each { |obj| @user4.like(obj) }

    # @user.similarity_with(@user5) should == -1.0
    [@movie1, @movie2, @movie3, @book4, @book5, @book6].each { |obj| @user5.dislike(obj) }
    [@book1, @book2, @book3, @movie4, @movie5, @movie6].each { |obj| @user5.like(obj) }

    # reset genre_type_weights
    Recommendable.config.genre_type_weights = {}
  end

  def test_similarity_between_calculates_correctly
    assert_equal Recommendable::Helpers::Calculations.similarity_between(@user.id, @user1.id), 1.0
    assert_equal Recommendable::Helpers::Calculations.similarity_between(@user.id, @user2.id), 0.25
    assert_equal Recommendable::Helpers::Calculations.similarity_between(@user.id, @user3.id), 0
    assert_equal Recommendable::Helpers::Calculations.similarity_between(@user.id, @user4.id), -0.25
    assert_equal Recommendable::Helpers::Calculations.similarity_between(@user.id, @user5.id), -1.0
  end

  def test_update_recommendations_ignores_rated_items
    Recommendable::Helpers::Calculations.update_similarities_for(@user.id)
    Recommendable::Helpers::Calculations.update_recommendations_for(@user.id)

    movies = @user.liked_movies + @user.disliked_movies
    books  = @user.liked_books  + @user.disliked_books

    movies.each { |m| refute_includes @user.recommended_movies, m }
    books.each  { |b| refute_includes @user.recommended_books,  b }
  end

  def test_predict_for_returns_predictions
    Recommendable::Helpers::Calculations.update_similarities_for(@user.id)
    assert_equal Recommendable::Helpers::Calculations.predict_for(@user.id, @book7.class, @book7.id), 1.0
    assert_equal Recommendable::Helpers::Calculations.predict_for(@user.id, @book8.class, @book8.id), 1.0
    assert_equal Recommendable::Helpers::Calculations.predict_for(@user.id, @book9.class, @book9.id), -1.0
    assert_equal Recommendable::Helpers::Calculations.predict_for(@user.id, @book10.class, @book10.id), -1.0
    assert_equal Recommendable::Helpers::Calculations.predict_for(@user.id, @movie7.class, @movie7.id), -1.0
    assert_equal Recommendable::Helpers::Calculations.predict_for(@user.id, @movie8.class, @movie8.id), -1.0
    assert_equal Recommendable::Helpers::Calculations.predict_for(@user.id, @movie9.class, @movie9.id), 1.0
    assert_equal Recommendable::Helpers::Calculations.predict_for(@user.id, @movie10.class, @movie10.id), 1.0
  end

  ### Custom Test
    def test_genre_type_weighting_similarity_between_calculates_crrectly
    Recommendable.config.genre_type_weights = {Movie: 10, Book: 1}

    # custom user for weight
    @weight_user = Factory(:user)
    [@movie1, @movie2, @movie3, @book4, @book5, @book6].each { |obj| @weight_user.like(obj) }
    # custom like_user
    5.times  { |x| instance_variable_set(:"@like_user#{x+1}",  Factory(:user))  }
    [@movie1, @movie2, @movie3, @book4, @book5, @book6, @book7, @book8, @movie9, @movie10].each { |obj| @like_user1.like(obj) }
    [@movie1, @movie2, @movie3, @book4, @book5 ].each { |obj| @like_user2.like(obj) }
    [@movie1, @movie2, @movie3].each { |obj| @like_user3.like(obj) }
    [@book4, @book5, @book6].each { |obj| @like_user4.like(obj) }
    [@movie1, @movie2, @book4, @book5, @book6].each { |obj| @like_user5.like(obj) }

    assert_equal Recommendable::Helpers::Calculations.similarity_between(@weight_user.id, @like_user1.id), 5.5
    assert_equal Recommendable::Helpers::Calculations.similarity_between(@weight_user.id, @like_user2.id), 5.333333333333333
    assert_equal Recommendable::Helpers::Calculations.similarity_between(@weight_user.id, @like_user3.id), 5.0
    assert_equal Recommendable::Helpers::Calculations.similarity_between(@weight_user.id, @like_user4.id), 0.5
    assert_equal Recommendable::Helpers::Calculations.similarity_between(@weight_user.id, @like_user5.id), 3.8333333333333335

    Recommendable.config.genre_type_weights = {}
  end

  def test_each_genre_weighting_similarity_between_calculates_crrectly_single_case
    # custom user for weight
    @weight_user = Factory(:user)
    [@movie1, @movie2, @movie3].each { |obj| @weight_user.weighted_like(obj, 1.0) }
    # custom like_user
    5.times  { |x| instance_variable_set(:"@like_user#{x+1}",  Factory(:user))  }
    [@movie1, @movie2, @movie3].each { |obj| @like_user1.weighted_like(obj, 1.0) }
    [@movie1, @movie2].each { |obj| @like_user2.weighted_like(obj, 1.0) }
    [@movie1].each { |obj| @like_user3.weighted_like(obj, 1.0) }
    [@movie1, @movie2, @movie3].each { |obj| @like_user4.weighted_like(obj, 0.5) }
    [@movie1, @movie2, @movie3].each { |obj| @like_user5.weighted_like(obj, 0.1) }

    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user1.id), 1.0
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user2.id), 0.6666666666666666
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user3.id), 0.3333333333333333
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user4.id), 0.75
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user5.id), 0.55
  end

  def test_each_genre_weighting_similarity_between_calculates_crrectly_multi_case
    # custom user for weight
    @weight_user = Factory(:user)
    [@movie1, @movie2, @movie3, @book1, @book2].each { |obj| @weight_user.weighted_like(obj, 1.0) }
    # custom like_user
    5.times  { |x| instance_variable_set(:"@like_user#{x+1}",  Factory(:user))  }
    [@movie1, @movie2, @movie3, @book1, @book2].each { |obj| @like_user1.weighted_like(obj, 1.0) }
    [@movie1, @movie2, @book1].each { |obj| @like_user2.weighted_like(obj, 1.0) }
    [@movie1, @book1].each { |obj| @like_user3.weighted_like(obj, 1.0) }
    [@movie1, @movie2, @movie3, @book1].each { |obj| @like_user4.weighted_like(obj, 0.5) }
    [@movie1, @movie2, @movie3, @book1].each { |obj| @like_user5.weighted_like(obj, 0.1) }

    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user1.id), 2.0
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user2.id), 1.1666666666666665
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user3.id), 0.8333333333333333
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user4.id), 1.125
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user5.id), 0.8250000000000001
  end

  def test_genre_type_weighting_and_each_genre_weighting_similarity_between_calculates_crrectly_multi_case
    Recommendable.config.genre_type_weights = {Movie: 10, Book: 1}

    # custom user for weight
    @weight_user = Factory(:user)
    [@movie1, @movie2, @movie3, @book1, @book2].each { |obj| @weight_user.weighted_like(obj, 1.0) }
    # custom like_user
    5.times  { |x| instance_variable_set(:"@like_user#{x+1}",  Factory(:user))  }
    [@movie1, @movie2, @movie3, @book1, @book2].each { |obj| @like_user1.weighted_like(obj, 1.0) }
    [@movie1, @movie2, @book1].each { |obj| @like_user2.weighted_like(obj, 1.0) }
    [@movie1, @book1].each { |obj| @like_user3.weighted_like(obj, 1.0) }
    [@movie1, @movie2, @movie3, @book1].each { |obj| @like_user4.weighted_like(obj, 0.5) }
    [@movie1, @movie2, @movie3, @book1].each { |obj| @like_user5.weighted_like(obj, 0.1) }

    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user1.id), 11.0
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user2.id), 7.166666666666667
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user3.id), 3.8333333333333335
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user4.id), 7.875
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user5.id), 5.775
  end

  def test_genre_type_weighting_and_each_genre_weighting_similarity_update_crrectly_multi_case
    Recommendable.config.genre_type_weights = {Movie: 10, Book: 1}

    # custom user for weight
    @weight_user = Factory(:user)
    [@movie1, @movie2, @movie3, @book1, @book2].each { |obj| @weight_user.weighted_like(obj, 1.0) }
    # custom like_user
    5.times  { |x| instance_variable_set(:"@like_user#{x+1}",  Factory(:user))  }
    [@movie1, @movie2, @movie3, @book1, @book2].each { |obj| @like_user1.weighted_like(obj, 1.0) }
    [@movie1, @movie2, @book1].each { |obj| @like_user2.weighted_like(obj, 1.0) }
    [@movie1, @book1].each { |obj| @like_user3.weighted_like(obj, 1.0) }
    [@movie1, @movie2, @movie3, @book1].each { |obj| @like_user4.weighted_like(obj, 0.5) }
    [@movie1, @movie2, @movie3, @book1].each { |obj| @like_user5.weighted_like(obj, 0.1) }

    Recommendable::Helpers::Calculations.update_weighted_similarities_for(@weight_user.id)

    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user1.id), 11.0
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user2.id), 7.166666666666667
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user3.id), 3.8333333333333335
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user4.id), 7.875
    assert_equal Recommendable::Helpers::Calculations.weighted_similarity_between(@weight_user.id, @like_user5.id), 5.775
  end

  def teardown
    Recommendable.redis.flushdb
  end
end
