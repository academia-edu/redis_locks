require 'digest'

module RedisLocks
  class RateLimitExceeded < ResourceUnavailable
    def initialize(key, rps)
      super("Rate limit of #{rps}/second on [#{key}] exceeded!")
    end
  end

  class TokenBucket

    NAMESPACE = "token-bucket"

    SCRIPT = <<-LUA
      local epoch = tonumber(ARGV[1])
      local rps = tonumber(ARGV[2])
      local burst = tonumber(ARGV[3])
      local key = KEYS[1]

      local token = 1.0 / rps
      local t = redis.call('get', key)
      if not t then
        t = epoch
      else
        t = tonumber(t)
      end

      if t < epoch then
        t = epoch
      elseif t > (epoch + (burst * token)) then
        return 0
      end

      redis.call('set', key, t + token)
      return 1
    LUA

    DIGEST = Digest::SHA1.hexdigest(SCRIPT)

    # `number` tokens are added to the bucket every `period` seconds (up to a
    # max of `number` tokens being available). Each time a resource is used, a
    # token is removed from the bucket; if no tokens are available, no resource
    # may be used.
    def initialize(key, redis:, period: 1, number: 1)
      @key = "#{NAMESPACE}:#{key}".freeze
      @rps = number.to_f / period.to_i
      @burst = number.to_i
      @redis = redis
    end

    def take
      epoch_i, microseconds = @redis.time
      epoch_f = epoch_i + (microseconds.to_f/1_000_000)
      took = RedisLocks.evalsha_or_eval(
        redis: @redis,
        script: SCRIPT,
        digest: DIGEST,
        keys: [@key],
        args: [epoch_f, @rps, @burst]
      )
      took == 1
    end

    def take!
      raise RateLimitExceeded.new(@key, @rps) unless take
    end

  end
end
