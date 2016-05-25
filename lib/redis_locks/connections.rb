require 'connection_pool'

module RedisLocks
  module Connections

    def self.ensure_pool(redis)
      if redis.respond_to?(:with)
        redis
      else
        ConnectionPool.new { redis.dup }
      end
    end

  end
end
