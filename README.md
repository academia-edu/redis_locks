# redis-locks
Various locking utilities for Ruby using Redis.

All classes are designed to work with Ruby clients distributed across multiple
processes and/or machines, but assume a single Redis master for correctness.

Works with Redis 2.6+.

# Utilities

## RedisLocks::Mutex

A simple mutex using `setnx`.

```ruby
  require 'redis'
  require 'redis_locks'

  RedisLocks.redis = Redis.new

  lock = RedisLocks::Mutex.new('my_key')

  # high-level use
  lock.lock! do 
    # something that can only be done by one process at a time
  end

  # lower-level options
  lock.lock # acquires lock & returns true
  lock.lock # returns false, lock was not acquired
  lock.unlock # now lock can be acquired again
```

Supports lock expiry via an `expires_in` argument to the constructor or 
`expires_at` argument to `lock`/`lock!`. By default, locks expire after 24 hours.

## RedisLocks::Semaphore

A semaphore implemented with Lua and `lpop`/`blpop`. 

Supports multiple resources, waits to acquire a resource, and timeouts.

```ruby
  require 'redis'
  require 'redis_locks'

  RedisLocks.redis = Redis.new

  semaphore = RedisLocks::Semaphore.new('my_key', resources: 2)

  # high-level use
  semaphore.lock! do
    # something that can be done by at most two processes at a time
  end

  # will wait indefinitely for a resource to be free, if necessary (this
  # counter-intuitive use of zero values reflects that of Redis' `blpop`)
  semaphore.lock!(timeout: 0) { }

  # will wait up to 1 second for a resource to be free
  semaphore.lock!(timeout: 1) { }

  # lower-level options
  semaphore.lock # acquires resource & returns true
  semaphore.lock # acquires another resource & returns true
  semaphore.lock # returns false, no resources remain
  semaphore.unlock # frees a resource
```

Supports expiry via `stale_client_timeout` argument to the constructor.
By default, clients are timed out after 24 hours.

## RedisLocks::TokenBucket

A [token-bucket](https://en.wikipedia.org/wiki/Token_bucket) rate limiter implemented with Lua.

```ruby
  require 'redis'
  require 'redis_locks'

  RedisLocks.redis = Redis.new

  # allows up to two calls to `take`/`take!` every five seconds
  limiter = RedisLocks::TokenBucket.new('my_key', period: 5, number: 2)

  2.times { limiter.take! }

  limiter.take # false if zero microseconds have passed, true otherwise (in which case a new token has become available)
  limiter.take! # raises RateLimitExceeded

  sleep(5)

  limiter.take # true
```
