module Recommendable
  module Ratable
    module Likable
      # Fetch a list of users that have liked this item.
      #
      # @return [Array] a list of users that have liked this item
      def liked_by
        Recommendable.query(Recommendable.config.user_class, liked_by_ids)
      end

      # Get the number of users that have liked this item
      #
      # @return [Fixnum] the number of users that have liked this item
      def liked_by_count
        Recommendable.redis.scard(Recommendable::Helpers::RedisKeyMapper.liked_by_set_for(self.class, id))
      end

      # Get the IDs of users that have liked this item.
      #
      # @return [Array] the IDs of users that have liked this item
      def liked_by_ids
        Recommendable.redis.smembers(Recommendable::Helpers::RedisKeyMapper.liked_by_set_for(self.class, id))
      end

      # Custom method.
      def weighted_liked_by
        Recommendable.query(Recommendable.config.user_class, weighted_liked_by_ids)
      end

      def weighted_liked_by_ids
        Recommendable.redis.zrange(Recommendable::Helpers::RedisKeyMapper.weighted_liked_by_set_for(self.class, id), 0, -1)
      end

      def weighted_liked_by_count
        Recommendable.redis.zcard(Recommendable::Helpers::RedisKeyMapper.weighted_liked_by_set_for(self.class, id))
      end
    end
  end
end
