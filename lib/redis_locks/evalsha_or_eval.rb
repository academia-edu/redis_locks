module RedisLocks

  # This ensures that each Lua script is evaluated at most once; after it has
  # been evaluated, we will be able to call it just by passing its digest.
  def self.evalsha_or_eval(redis:, script:, digest:, keys: [], args: [])
    redis.evalsha digest, keys, args
  rescue Redis::CommandError => e
    if e.message.start_with?('NOSCRIPT')
      redis.eval script, keys, args
    else
      raise
    end
  end

end
