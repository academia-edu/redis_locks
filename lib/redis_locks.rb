require 'redis_locks/version'
require 'redis_locks/resource_unavailable'
require 'redis_locks/evalsha_or_eval'
require 'redis_locks/mutex'
require 'redis_locks/semaphore'
require 'redis_locks/token_bucket'
require 'redis_locks/connections'

module RedisLocks

  def self.redis=(redis)
    @redis = Connections.ensure_pool(redis)
  end

  def self.redis
    raise "RedisLocks.redis is not set!" unless @redis
    @redis
  end

end
