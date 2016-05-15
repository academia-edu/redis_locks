# Adapted from https://github.com/dv/redis-semaphore - switched to use Lua
# instead of broken mutex implementation, see issue #23 on GitHub.
#
# Options we don't use were removed for simplicity.
#
# Original copyright (C) 2011 by David Verhasselt (david@crowdway.com)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
require 'digest'

module RedisLocks
  class SemaphoreUnavailable < ResourceUnavailable
    def initialize(key, resources)
      super("Key [#{key}] has 0/#{resources} resources available!")
    end
  end

  class Semaphore

    NAMESPACE = "semaphore-lua"

    # Removes stale locks, then ensures that all resources which aren't locked
    # are marked as available.
    SETUP_SCRIPT = <<-LUA
      local avail_key = KEYS[1]
      local grabbed_key = KEYS[2]

      local expected_resources = tonumber(ARGV[1])
      local stale_before = tonumber(ARGV[2])

      redis.call('zremrangebyscore', grabbed_key, -1, stale_before)

      local found_resources = redis.call('llen', avail_key) + redis.call('zcard', grabbed_key)
      if found_resources < expected_resources then
        for i=1,(expected_resources - found_resources) do
          redis.call('rpush', avail_key, 1)
        end
      end
    LUA

    SETUP_DIGEST = Digest::SHA1.hexdigest(SETUP_SCRIPT)

    # `resources` is the number of clients allowed to lock the semaphore
    # concurrently.
    #
    # `stale_client_timeout` is the threshold of time before we assume that
    # something has gone terribly wrong with a client and we invalidate its lock.
    def initialize(key, redis:, resources: 1, stale_client_timeout: 86400)
      @key = key
      @resource_count = resources.to_i
      @stale_client_timeout = stale_client_timeout.to_f
      @redis = redis
      @tokens = []

      raise ArgumentError.new("Lock key is required") if @key.nil? || @key.empty?
      raise ArgumentError.new("resources must be > 0") unless @resource_count > 0
      raise ArgumentError.new("stale_client_timeout must be > 0") unless @stale_client_timeout > 0
    end

    # Forcefully clear the lock. Be careful!
    def delete!
      @redis.del(available_key)
      @redis.del(grabbed_key)
      @tokens = []
    end

    # Acquire a resource from the semaphore, if available. Returns false if no
    # resources are available.
    #
    # `timeout` is how long to wait, blocking, until a resource is available.
    # The default is nil, meaning don't block. A timeout of zero means block forever.
    # (This is a bit weird, but corresponds to how blpop uses timeout values.)
    #
    # If passed a block, if a resource is available, runs the block and then
    # unlocks.
    #
    # If called without a block, if a resource is available, returns a token.
    # Caller is then responsible for unlocking the token.
    #
    # This isn't atomic--if the process dies, we could remove something from the
    # available queue without adding it to the grabbed set--but that's ok, the
    # semaphore will recover just as if this was a stale client that left its
    # token in the grabbed set forever.
    def lock(timeout: nil, &block)
      ensure_exists_and_release_stale_locks!

      success =
        if timeout
          !@redis.blpop(available_key, timeout.to_i).nil?
        else
          !@redis.lpop(available_key).nil?
        end

      return false unless success

      token = SecureRandom.hex(16)
      @tokens.push(token)
      @redis.zadd(grabbed_key, epoch_f, token)

      return_or_yield(token, &block)
    end

    def wait(timeout: 0, &block)
      lock(timeout: timeout, &block)
    end

    def lock!(timeout: nil, &block)
      token = lock(timeout: timeout)
      raise SemaphoreUnavailable.new(@key, @resource_count) unless token
      return_or_yield(token, &block)
    end

    def wait!(timeout: 0, &block)
      lock!(timeout: timeout, &block)
    end

    # Release a resource back to the semaphore. Should normally be called with an
    # explicit token.
    #
    # This isn't atomic--if the process dies, we could remove something from the
    # blocked set without adding it to the available queue--but that's ok, the
    # semaphore will recover just as if this was a stale client that left its
    # token in the grabbed set forever.
    def unlock(token = @tokens.pop)
      return unless token

      removed = @redis.zrem grabbed_key, token
      if removed
        @redis.lpush available_key, 1
      end

      removed
    end
    alias_method :signal, :unlock

    private

    def return_or_yield(token)
      return_value = token
      if block_given?
        begin
          return_value = yield token
        ensure
          unlock(token)
        end
      end
      return_value
    end

    def ensure_exists_and_release_stale_locks!
      RedisLocks.evalsha_or_eval(
        redis: @redis,
        script: SETUP_SCRIPT,
        digest: SETUP_DIGEST,
        keys: [available_key, grabbed_key],
        args: [@resource_count, stale_before]
      )
    end

    def namespaced_key(variable)
      "#{NAMESPACE}:#{@key}:#{variable}"
    end

    def available_key
      @available_key ||= namespaced_key('AVAILABLE')
    end

    def grabbed_key
      @grabbed_key ||= namespaced_key('GRABBED')
    end

    def stale_before
      epoch_f - @stale_client_timeout
    end

    def epoch_f
      epoch_i, microseconds = @redis.time
      epoch_i + microseconds.to_f / 1_000_000
    end

  end
end
