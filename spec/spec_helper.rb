require 'rubygems'
require 'bundler/setup'
require 'pry'
require 'redis'
require 'redis_locks'
require 'thread'

$redis = Redis.new(db: ENV['REDIS_LOCKS_SPEC_DB'] || 15)

raise "#{$redis.inspect} is non-empty!" if $redis.keys.any?

RSpec.configure do |config|
  config.after(:each) do
    $redis.flushdb
  end
end
