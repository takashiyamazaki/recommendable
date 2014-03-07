module Recommendable
  module Helpers
    module Calculations
      class << self
        # Calculate a numeric similarity value that can fall between -1.0 and 1.0.
        # A value of 1.0 indicates that both users have rated the same items in
        # the same ways. A value of -1.0 indicates that both users have rated the
        # same items in opposite ways.
        #
        # @param [Fixnum, String] user_id the ID of the first user
        # @param [Fixnum, String] other_user_id the ID of another user
        # @return [Float] the numeric similarity between this user and the passed user
        # @note Similarity values are asymmetrical. `Calculations.similarity_between(user_id, other_user_id)` will not necessarily equal `Calculations.similarity_between(other_user_id, user_id)`
        def similarity_between(user_id, other_user_id)
          user_id = user_id.to_s
          other_user_id = other_user_id.to_s

          similarity = liked_count = disliked_count = 0
          in_common = Recommendable.config.ratable_classes.each do |klass|
            genre_type_weight = Recommendable.config.genre_type_weights.fetch(klass.to_s.to_sym, 1).to_f

            liked_set = Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, user_id)
            other_liked_set = Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, other_user_id)
            disliked_set = Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, user_id)
            other_disliked_set = Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, other_user_id)

            # Agreements
            similarity += Recommendable.redis.sinter(liked_set, other_liked_set).size * genre_type_weight
            similarity += Recommendable.redis.sinter(disliked_set, other_disliked_set).size * genre_type_weight

            # Disagreements
            similarity -= Recommendable.redis.sinter(liked_set, other_disliked_set).size * genre_type_weight
            similarity -= Recommendable.redis.sinter(disliked_set, other_liked_set).size * genre_type_weight

            liked_count += Recommendable.redis.scard(liked_set)
            disliked_count += Recommendable.redis.scard(disliked_set)
          end

          similarity / (liked_count + disliked_count).to_f
        end

        def weighted_similarity_between(user_id, other_user_id)
          user_id = user_id.to_s
          other_user_id = other_user_id.to_s

          similarity = liked_count = disliked_count = 0
          in_common = Recommendable.config.ratable_classes.each do |klass|
            genre_type_weight = Recommendable.config.genre_type_weights.fetch(klass.to_s.to_sym, 1).to_f

            weighted_liked_zset = Recommendable::Helpers::RedisKeyMapper.weighted_liked_set_for(klass, user_id)
            other_weighted_liked_zset = Recommendable::Helpers::RedisKeyMapper.weighted_liked_set_for(klass, other_user_id)
            zinter_temp_zset = Recommendable::Helpers::RedisKeyMapper.zinter_temp_set_for(klass, user_id)

            # Agreements
            Recommendable.redis.zinterstore(zinter_temp_zset, [weighted_liked_zset, other_weighted_liked_zset], :aggregate => "sum")
            common_ids_with_score = Recommendable.redis.zrange(zinter_temp_zset, 0, -1, :with_scores => true)

            genre_similarity = common_ids_with_score.inject(0){|sum, id_with_score| sum + (id_with_score[1].to_f / 2.0)} * genre_type_weight

            liked_count = Recommendable.redis.zcard(weighted_liked_zset) * Recommendable.config.chara_fever_max_weight

            Recommendable.redis.del(zinter_temp_zset)

            similarity += genre_similarity / liked_count.to_f if liked_count != 0
          end

          similarity
        end        

        # Used internally to update the similarity values between this user and all
        # other users. This is called by the background worker.
        def update_similarities_for(user_id)
          user_id = user_id.to_s # For comparison. Redis returns all set members as strings.
          similarity_set = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)

          # Only calculate similarities for users who have rated the items that
          # this user has rated
          relevant_user_ids = Recommendable.config.ratable_classes.inject([]) do |memo, klass|
            liked_set = Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, user_id)
            disliked_set = Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, user_id)

            item_ids = Recommendable.redis.sunion(liked_set, disliked_set)

            unless item_ids.empty?
              sets = item_ids.map do |id|
                liked_by_set = Recommendable::Helpers::RedisKeyMapper.liked_by_set_for(klass, id)
                disliked_by_set = Recommendable::Helpers::RedisKeyMapper.disliked_by_set_for(klass, id)

                [liked_by_set, disliked_by_set]
              end

              memo | Recommendable.redis.sunion(*sets.flatten)
            else
              memo
            end
          end

          relevant_user_ids.each do |id|
            next if id == user_id # Skip comparing with self.
            Recommendable.redis.zadd(similarity_set, similarity_between(user_id, id), id)
          end

          if knn = Recommendable.config.nearest_neighbors
            length = Recommendable.redis.zcard(similarity_set)
            kfn = Recommendable.config.furthest_neighbors || 0

            Recommendable.redis.zremrangebyrank(similarity_set, kfn, length - knn - 1)
          end

          true
        end

        def update_weighted_similarities_for(user_id)
          user_id = user_id.to_s # For comparison. Redis returns all set members as strings.
          similarity_set = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)

          # Only calculate similarities for users who have rated the items that
          # this user has rated
          relevant_user_ids = Recommendable.config.ratable_classes.inject([]) do |memo, klass|
            weighted_liked_zset = Recommendable::Helpers::RedisKeyMapper.weighted_liked_set_for(klass, user_id)

            item_ids = Recommendable.redis.zrange(weighted_liked_zset, 0, -1)

            unless item_ids.empty?
              zsets = item_ids.map do |id|
                weighted_liked_by_set = Recommendable::Helpers::RedisKeyMapper.weighted_liked_by_set_for(klass, id)

                weighted_liked_by_set
              end

              zunion_temp_zset = Recommendable::Helpers::RedisKeyMapper.zinter_temp_set_for(klass, user_id)
              Recommendable.redis.zunionstore(zunion_temp_zset, zsets)
              zunion_set = Recommendable.redis.zrange(zunion_temp_zset, 0, -1)
              Recommendable.redis.del(zunion_temp_zset)

              memo | zunion_set
            else
              memo
            end
          end

          relevant_user_ids.each do |id|
            next if id == user_id # Skip comparing with self.
            Recommendable.redis.zadd(similarity_set, weighted_similarity_between(user_id, id), id)
          end

          if knn = Recommendable.config.nearest_neighbors
            length = Recommendable.redis.zcard(similarity_set)
            kfn = Recommendable.config.furthest_neighbors || 0

            Recommendable.redis.zremrangebyrank(similarity_set, kfn, length - knn - 1)
          end

          true
        end        

        # Used internally to update this user's prediction values across all
        # recommendable types. This is called by the background worker.
        #
        # @private
        def update_recommendations_for(user_id)
          user_id = user_id.to_s

          nearest_neighbors = Recommendable.config.nearest_neighbors || Recommendable.config.user_class.count
          Recommendable.config.ratable_classes.each do |klass|
            rated_sets = [
              Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, user_id),
              Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, user_id),
              Recommendable::Helpers::RedisKeyMapper.hidden_set_for(klass, user_id),
              Recommendable::Helpers::RedisKeyMapper.bookmarked_set_for(klass, user_id)
            ]
            temp_set = Recommendable::Helpers::RedisKeyMapper.temp_set_for(Recommendable.config.user_class, user_id)
            similarity_set  = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)
            recommended_set = Recommendable::Helpers::RedisKeyMapper.recommended_set_for(klass, user_id)
            most_similar_user_ids = Recommendable.redis.zrevrange(similarity_set, 0, nearest_neighbors - 1)
            least_similar_user_ids = Recommendable.redis.zrange(similarity_set, 0, nearest_neighbors - 1)

            # Get likes from the most similar users
            sets_to_union = most_similar_user_ids.inject([]) do |sets, id|
              sets << Recommendable::Helpers::RedisKeyMapper.liked_set_for(klass, id)
            end

            # Get dislikes from the least similar users
            least_similar_user_ids.inject(sets_to_union) do |sets, id|
              sets << Recommendable::Helpers::RedisKeyMapper.disliked_set_for(klass, id)
            end

            return if sets_to_union.empty?

            # SDIFF rated items so they aren't recommended
            Recommendable.redis.sunionstore(temp_set, *sets_to_union)
            item_ids = Recommendable.redis.sdiff(temp_set, *rated_sets)
            scores = item_ids.map { |id| [predict_for(user_id, klass, id), id] }
            scores.each do |s|
              Recommendable.redis.zadd(recommended_set, s[0], s[1])
            end

            Recommendable.redis.del(temp_set)

            if number_recommendations = Recommendable.config.recommendations_to_store
              length = Recommendable.redis.zcard(recommended_set)
              Recommendable.redis.zremrangebyrank(recommended_set, 0, length - number_recommendations - 1)
            end
          end

          true
        end

        # Predict how likely it is that a user will like an item. This probability
        # is not based on percentage. 0.0 indicates that the user will neither like
        # nor dislike the item. Values that approach Infinity indicate a rising
        # likelihood of liking the item while values approaching -Infinity
        # indicate a rising probability of disliking the item.
        #
        # @param [Fixnum, String] user_id the user's ID
        # @param [Class] klass the item's class
        # @param [Fixnum, String] item_id the item's ID
        # @return [Float] the probability that the user will like the item
        def predict_for(user_id, klass, item_id)
          user_id = user_id.to_s
          item_id = item_id.to_s

          similarity_set = Recommendable::Helpers::RedisKeyMapper.similarity_set_for(user_id)
          liked_by_set = Recommendable::Helpers::RedisKeyMapper.liked_by_set_for(klass, item_id)
          disliked_by_set = Recommendable::Helpers::RedisKeyMapper.disliked_by_set_for(klass, item_id)
          similarity_sum = 0.0

          similarity_sum += Recommendable.redis.smembers(liked_by_set).inject(0) do |memo, id|
            memo += Recommendable.redis.zscore(similarity_set, id).to_f
          end

          similarity_sum += Recommendable.redis.smembers(disliked_by_set).inject(0) do |memo, id|
            memo -= Recommendable.redis.zscore(similarity_set, id).to_f
          end

          liked_by_count = Recommendable.redis.scard(liked_by_set)
          disliked_by_count = Recommendable.redis.scard(disliked_by_set)
          prediction = similarity_sum / (liked_by_count + disliked_by_count).to_f
          prediction.finite? ? prediction : 0.0
        end

        def update_score_for(klass, id)
          score_set = Recommendable::Helpers::RedisKeyMapper.score_set_for(klass)
          liked_by_set = Recommendable::Helpers::RedisKeyMapper.liked_by_set_for(klass, id)
          disliked_by_set = Recommendable::Helpers::RedisKeyMapper.disliked_by_set_for(klass, id)
          liked_by_count = Recommendable.redis.scard(liked_by_set)
          disliked_by_count = Recommendable.redis.scard(disliked_by_set)

          return 0.0 unless liked_by_count + disliked_by_count > 0

          z = 1.96
          n = liked_by_count + disliked_by_count
          phat = liked_by_count / n.to_f

          begin
            score = (phat + z*z/(2*n) - z * Math.sqrt((phat*(1-phat)+z*z/(4*n))/n))/(1+z*z/n)
          rescue Math::DomainError
            score = 0
          end

          Recommendable.redis.zadd(score_set, score, id)
          true
        end
      end
    end
  end
end
