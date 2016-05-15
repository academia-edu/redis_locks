$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "redis_locks/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "redis_locks"
  s.version     = RedisLocks::VERSION
  s.authors     = ["Academia.edu"]
  s.email       = ["david@academia.edu"]
  s.homepage    = "https://github.com/academia-edu/redis_locks"
  s.summary     = "Various locking utilities for Ruby using Redis"
  s.description = "Various locking utilities for Ruby using Redis, including a mutex, a semaphore, and a token bucket rate limiter"
  s.license     = "MIT"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency "redis"

  s.add_development_dependency "rspec"
  s.add_development_dependency "rake"
end
