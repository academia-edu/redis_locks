module RedisLocks
  class AlreadyLocked < ResourceUnavailable
    def initialize(key)
      super("Key [#{key}] already locked!")
    end
  end

  class Mutex

    NAMESPACE = "mutex"

    def initialize(key, redis:, expires_in: 86400)
      @key = "#{NAMESPACE}:#{key}"
      @redis = redis
      @expires_in = expires_in.to_i

      raise ArgumentError.new("Invalid expires_in: #{expires_in}") unless expires_in > 0
    end

    def lock(expires_at: nil, &block)
      now = Time.now.utc.to_i
      locked = false
      expires_at ||= now + @expires_in

      if @redis.setnx(@key, expires_at)
        @redis.expire(@key, expires_at - now)
        locked = true
      else # it was locked
        if (old_value = @redis.get(@key)).to_i <= now
          # lock has expired
          if @redis.getset(@key, expires_at) == old_value
            locked = true
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
      @redis.watch(@key) do
        # only delete the key if it's still valid, and will be for another 2 seconds
        if @redis.get(@key).to_i > Time.now.utc.to_i + 2
          @redis.multi do |multi|
            multi.del(@key)
          end
        else
          @redis.unwatch
        end
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
