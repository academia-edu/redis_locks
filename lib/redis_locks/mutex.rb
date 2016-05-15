module RedisLocks
  class AlreadyLocked < ResourceUnavailable
    def initialize(key)
      super("Key [#{key}] already locked!")
    end
  end

  class Mutex

    NAMESPACE = "mutex"

    def initialize(key, redis:, expires_in: 86400, expires_at: nil)
      @key = "#{NAMESPACE}:#{key}"
      @redis = redis
      @expires_at = (expires_at.to_i if expires_at) || (Time.now.utc.to_i + expires_in)
    end

    def lock(&block)
      now = Time.now.utc.to_i
      locked = false

      if @redis.setnx(@key, @expires_at)
        @redis.expire(@key, @expires_at - now)
        locked = true
      else # it was locked
        if (old_value = @redis.get(@key)).to_i <= now
          # lock has expired
          if @redis.getset_value(@key, @expires_at) == old_value
            locked = true
          end
        end
      end

      return false unless locked

      return_or_yield(&block)
    end

    def lock!(&block)
      locked = lock
      raise AlreadyLocked.new(@key) unless locked
      return_or_yield(&block)
    end

    # only delete the key if it's still valid, and will be for another 2 seconds
    def unlock
      if Time.now.utc.to_i - 2 < @expires_at
        @redis.del(@key)
      end
    end

    private

    def return_or_yield
      return_value = true
      if block_given?
        begin
          return_value = yield
        ensure
          unlock
        end
      end
      return_value
    end
  end
end
