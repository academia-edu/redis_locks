module RedisLocks
  class AlreadyLocked < ResourceUnavailable
    def initialize(key)
      super("Key [#{key}] already locked!")
    end
  end

  class Mutex

    NAMESPACE = "mutex"

    def initialize(key, expires_in: 86400, redis: RedisLocks.redis)
      @key = "#{NAMESPACE}:#{key}"
      @redis = Connections.ensure_pool(redis)
      @expires_in = expires_in.to_i

      raise ArgumentError.new("Invalid expires_in: #{expires_in}") unless expires_in > 0
    end

    def lock(expires_at: nil, &block)
      now = Time.now.utc.to_i
      locked = false

      if expires_at
        expires_at = expires_at.to_i
      else
        expires_at = now + @expires_in
      end

      @redis.with do |conn|
        if conn.setnx(@key, expires_at)
          conn.expire(@key, expires_at - now)
          @expires_at = expires_at
          locked = true
        else # it was locked
          if (old_value = conn.get(@key)).to_i <= now
            # lock has expired
            if conn.getset(@key, expires_at) == old_value
              @expires_at = expires_at
              locked = true
            end
          end
        end
      end

      return false unless locked

      return_or_yield(&block)
    end

    def lock!(expires_at: nil, &block)
      locked = lock(expires_at: expires_at)
      raise AlreadyLocked.new(@key) unless locked
      return_or_yield(&block)
    end

    def unlock
      return unless @expires_at

      # To prevent deleting a lock acquired from another process, only delete
      # the key if it's still valid, and will be for another 2 seconds
      if Time.now.utc.to_i - 2 < @expires_at
        @redis.with { |conn| conn.del(@key) }
      end

      @expires_at = nil
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
